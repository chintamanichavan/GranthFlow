#import "AFEngine.h"

#include <string>
#include <vector>

#include "core/engine.hpp"

@implementation AFCommand {
    NSString *_name, *_usage, *_help;
}
- (instancetype)initWithName:(NSString *)name usage:(NSString *)usage help:(NSString *)help {
    if ((self = [super init])) { _name = name; _usage = usage; _help = help; }
    return self;
}
- (NSString *)name { return _name; }
- (NSString *)usage { return _usage; }
- (NSString *)help { return _help; }
@end

@implementation AFResult {
    int _status; NSString *_output, *_errorText; NSData *_data, *_outputData;
}
- (instancetype)initWithStatus:(int)status output:(NSString *)output error:(NSString *)error data:(NSData *)data outputData:(NSData *)outputData {
    if ((self = [super init])) { _status = status; _output = output; _errorText = error; _data = data; _outputData = outputData; }
    return self;
}
- (int)status { return _status; }
- (NSString *)output { return _output; }
- (NSString *)errorText { return _errorText; }
- (NSData *)data { return _data; }
- (NSData *)outputData { return _outputData; }
@end

static NSString *str(const std::string &s) {
    // Engine output is UTF-8 unless a binary file leaks bytes into it; fall back to Latin-1 so nothing is lost.
    NSString *u = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return u ?: [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSISOLatin1StringEncoding] ?: @"";
}

static std::string bytes(NSData *data) {
    return std::string(static_cast<const char *>(data.bytes), data.length);
}

// Everything below is translation between Objective-C and C++ types. The work itself lives in
// anyfile::detectKind / commandsForKind / runOnBytes, which the WebAssembly build also calls.
@implementation AFEngine

+ (NSString *)detectKind:(NSData *)data name:(NSString *)name {
    return str(anyfile::detectKind(bytes(data), name.UTF8String));
}

+ (NSArray<AFCommand *> *)commandsForKind:(NSString *)kind {
    NSMutableArray<AFCommand *> *out = [NSMutableArray array];
    for (const auto &c : anyfile::commandsForKind(kind.UTF8String)) {
        [out addObject:[[AFCommand alloc] initWithName:str(c.name) usage:str(c.usage) help:str(c.help)]];
    }
    return out;
}

+ (AFResult *)run:(NSString *)command args:(NSArray<NSString *> *)args data:(NSData *)data name:(NSString *)name kind:(NSString *)kind {
    std::vector<std::string> argv;
    argv.reserve(args.count);
    for (NSString *arg in args) argv.push_back(arg.UTF8String);

    const anyfile::RunResult r = anyfile::runOnBytes(command.UTF8String, argv, bytes(data), name.UTF8String,
                                                     kind.length ? kind.UTF8String : "");
    NSData *changed = r.didChange ? [NSData dataWithBytes:r.changed.data() length:r.changed.size()] : nil;
    return [[AFResult alloc] initWithStatus:static_cast<int>(r.status) output:str(r.output) error:str(r.error) data:changed
                                 outputData:[NSData dataWithBytes:r.output.data() length:r.output.size()]];
}

@end
