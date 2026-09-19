#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 把 ObjC 异常（NSException）转成 NSError，避免 Swift 调用的系统 API
/// 直接抛异常把 App 崩掉（AVAudioEngine、Speech 这类框架常见）。
@interface ObjCExceptionCatcher : NSObject

/// 执行 block；若抛出 NSException，返回 NO 并回填 error。
+ (BOOL)perform:(void (^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
