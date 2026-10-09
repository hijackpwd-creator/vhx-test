#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>
#include <string.h>

@interface PLServerValidator : NSObject
@property(nonatomic, strong) NSURLSession *sharedSession;
@property(nonatomic) NSInteger expectedStatus;
- (BOOL)_pingServerVHX:(NSString *)base timeout:(double)timeout verbose:(BOOL)verbose;
@end

@implementation PLServerValidator
- (instancetype)init {
    if ((self = [super init])) {
        // The original session configuration was not supplied.
        _sharedSession = [NSURLSession sharedSession];
        _expectedStatus = 200;
    }
    return self;
}
- (BOOL)_pingServerVHX:(NSString *)base timeout:(double)timeout verbose:(BOOL)verbose {
    if (!base.length) return NO;
    if (!isfinite(timeout) || timeout <= 0 || timeout > 86400 ||
        self.expectedStatus < 100 || self.expectedStatus > 599 || !self.sharedSession) {
        if (verbose) fprintf(stderr, "Invalid timeout, expected status, or session\n");
        return NO;
    }
    NSString *target = [base stringByAppendingString:@"/vhx"];
    NSURL *url = [NSURL URLWithString:target];
    if (!url || !url.host.length ||
        !([url.scheme.lowercaseString isEqualToString:@"http"] ||
          [url.scheme.lowercaseString isEqualToString:@"https"])) {
        fprintf(stderr, "Invalid HTTP(S) URL\n");
        return NO;
    }
    __block BOOL success = NO;
    __block NSData *receivedData = nil;
    __block NSURLResponse *receivedResponse = nil;
    __block NSError *receivedError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = timeout;
    if (verbose) fprintf(stderr, "GET %s\nRequest timeout: %.3fs; wait limit: %.3fs\n",
                         target.UTF8String, timeout, timeout + 2.0);
    NSInteger expectedStatus = self.expectedStatus;
    NSURLSessionDataTask *task = [self.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response : nil;
            success = NO;
            if (!error && http && http.statusCode == expectedStatus && data.length > 0) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSString *trimmed = [body stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                // Explicit nil check: invalid UTF-8 must not pass via messaging nil.
                success = trimmed != nil && [trimmed caseInsensitiveCompare:@"ok"] == NSOrderedSame;
            }
            receivedData = data;
            receivedResponse = response;
            receivedError = error;
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];
    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 2.0) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, deadline) != 0) {
        [task cancel];
        if (verbose) fprintf(stderr, "Semaphore wait timed out; task cancelled\n");
        return NO;
    }
    if (verbose) {
        NSHTTPURLResponse *http = [receivedResponse isKindOfClass:[NSHTTPURLResponse class]]
            ? (NSHTTPURLResponse *)receivedResponse : nil;
        fprintf(stderr, "Final URL: %s\nHTTP status: %ld; expected: %ld\nResponse bytes: %lu\n",
            (receivedResponse.URL.absoluteString ?: @"(none)").UTF8String,
            (long)http.statusCode, (long)expectedStatus, (unsigned long)receivedData.length);
        if (receivedError) fprintf(stderr, "Error: %s (%ld): %s\n",
            receivedError.domain.UTF8String, (long)receivedError.code,
            receivedError.localizedDescription.UTF8String);
        fprintf(stderr, "Headers: %s\n", (http.allHeaderFields.description ?: @"(none)").UTF8String);
        // Raw byte preview: no UTF-8 boundary truncation or embedded-NUL loss.
        NSUInteger count = MIN(receivedData.length, (NSUInteger)4096);
        fprintf(stderr, "Body preview (raw bytes, up to 4096):\n");
        if (count) fwrite(receivedData.bytes, 1, count, stderr);
        fputc('\n', stderr);
    }
    return success;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 5) {
            fprintf(stderr, "Usage: %s <base-url> [timeout-seconds=5] [verbose=1] [expected-status=200]\n", argv[0]);
            return 2;
        }
        double timeout = 5.0;
        if (argc >= 3) {
            char *end = NULL;
            errno = 0;
            timeout = strtod(argv[2], &end);
            if (errno || end == argv[2] || *end || !isfinite(timeout) || timeout <= 0 || timeout > 86400) {
                fprintf(stderr, "Timeout must be a finite number in (0, 86400]\n");
                return 2;
            }
        }
        if (argc >= 4 && strcmp(argv[3], "0") && strcmp(argv[3], "1")) {
            fprintf(stderr, "Verbose must be 0 or 1\n");
            return 2;
        }
        NSString *base = [NSString stringWithUTF8String:argv[1]];
        PLServerValidator *validator = [[PLServerValidator alloc] init];
        if (argc == 5) {
            char *end = NULL;
            errno = 0;
            long status = strtol(argv[4], &end, 10);
            if (errno || end == argv[4] || *end || status < 100 || status > 599) {
                fprintf(stderr, "Expected status must be an integer in [100, 599]\n");
                return 2;
            }
            validator.expectedStatus = status;
        }
        NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
        BOOL ok = [validator _pingServerVHX:base timeout:timeout verbose:argc < 4 || !strcmp(argv[3], "1")];
        printf("RESULT=%s elapsed=%.3fs\n", ok ? "true" : "false", NSProcessInfo.processInfo.systemUptime - start);
        return ok ? 0 : 1;
    }
}
