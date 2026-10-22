// Objective-C face of the C++ engine. Swift sees only strings, arrays and NSData.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AFCommand : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *usage;
@property (nonatomic, readonly) NSString *help;
@end

@interface AFResult : NSObject
@property (nonatomic, readonly) int status;              // 0 ok, 1 error, 2 bad usage, 3 unknown command
@property (nonatomic, readonly) NSString *output;
@property (nonatomic, readonly) NSString *errorText;
@property (nonatomic, readonly, nullable) NSData *data;  // the file's new contents when the command changed it
@end

@interface AFEngine : NSObject
/// "pdf", "markdown", "text" or "binary", from magic bytes, the file name's extension, and content.
+ (NSString *)detectKind:(NSData *)data name:(NSString *)name;
/// Commands for a kind: the kind's own commands followed by the ones every file has.
+ (NSArray<AFCommand *> *)commandsForKind:(NSString *)kind;
/// Runs one command against in-memory contents. The data is written to a private temp file,
/// the handler runs on it, and the result carries the new bytes if the command changed them.
+ (AFResult *)run:(NSString *)command args:(NSArray<NSString *> *)args data:(NSData *)data name:(NSString *)name kind:(NSString *)kind;
@end

NS_ASSUME_NONNULL_END
