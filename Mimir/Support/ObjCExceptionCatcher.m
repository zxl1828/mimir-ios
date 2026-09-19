#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)perform:(void (^)(void))block error:(NSError **)error {
    @try {
        if (block) {
            block();
        }
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: @"未知异常";
            info[@"ExceptionName"] = exception.name ?: @"NSException";
            *error = [NSError errorWithDomain:@"MimirObjCException" code:1 userInfo:info];
        }
        return NO;
    }
}

@end
