#import "AFEngine.h"

#include <sstream>
#include <string>
#include <vector>

#include "core/handler.hpp"
#include "core/util.hpp"

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
    int _status; NSString *_output, *_errorText; NSData *_data;
}
- (instancetype)initWithStatus:(int)status output:(NSString *)output error:(NSString *)error data:(NSData *)data {
    if ((self = [super init])) { _status = status; _output = output; _errorText = error; _data = data; }
    return self;
}
- (int)status { return _status; }
- (NSString *)output { return _output; }
- (NSString *)errorText { return _errorText; }
- (NSData *)data { return _data; }
@end

static NSString *str(const std::string &s) {
    // Engine output is UTF-8 unless a binary file leaks bytes into it; fall back to Latin-1 so nothing is lost.
    NSString *u = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return u ?: [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSISOLatin1StringEncoding] ?: @"";
}

// A temp file that keeps the original extension (detection looks at it) and is removed on scope exit.
struct TempCopy {
    std::string path;
    TempCopy(NSData *data, NSString *name) {
        NSString *ext = name.pathExtension;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"anyfile-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *file = [dir stringByAppendingPathComponent:ext.length ? [@"file" stringByAppendingPathExtension:ext] : @"file"];
        [data writeToFile:file atomically:NO];
        path = file.UTF8String;
    }
    ~TempCopy() { [NSFileManager.defaultManager removeItemAtPath:[@(path.c_str()) stringByDeletingLastPathComponent] error:nil]; }
};

@implementation AFEngine

+ (NSString *)detectKind:(NSData *)data name:(NSString *)name {
    TempCopy tmp(data, name);
    std::string kind;
    anyfile::makeHandler(tmp.path, "", kind);
    return str(kind);
}

+ (NSArray<AFCommand *> *)commandsForKind:(NSString *)kind {
    std::string detected;
    auto h = anyfile::makeHandler("/nonexistent", kind.UTF8String, detected);   // a forced kind never touches the path
    NSMutableArray<AFCommand *> *out = [NSMutableArray array];
    auto add = [&](const std::vector<anyfile::Command> &cs) {
        for (const auto &c : cs) [out addObject:[[AFCommand alloc] initWithName:str(c.name) usage:str(c.usage) help:str(c.help)]];
    };
    if (h) add(h->commands());
    add(anyfile::commonCommands());
    return out;
}

+ (AFResult *)run:(NSString *)command args:(NSArray<NSString *> *)args data:(NSData *)data name:(NSString *)name kind:(NSString *)kind {
    TempCopy tmp(data, name);
    std::vector<std::string> argv;
    for (NSUInteger i = 0; i < args.count; ++i) {
        // --out would write outside the document; the GUI always edits in place.
        if ([args[i] isEqualToString:@"--out"] || [args[i] isEqualToString:@"-o"]) { ++i; continue; }
        argv.push_back(args[i].UTF8String);
    }
    std::string detected;
    auto h = anyfile::makeHandler(tmp.path, kind.length ? kind.UTF8String : "", detected);
    if (!h) return [[AFResult alloc] initWithStatus:2 output:@"" error:@"unknown file kind" data:nil];
    std::ostringstream out, err;
    anyfile::Status st = h->run(command.UTF8String, argv, out, err);
    if (st == anyfile::Status::Unknown) err << "\"" << command.UTF8String << "\" is not a command for " << detected << " files";

    NSData *after = [NSData dataWithContentsOfFile:@(tmp.path.c_str())];
    NSData *changed = (after && ![after isEqualToData:data]) ? after : nil;
    return [[AFResult alloc] initWithStatus:static_cast<int>(st) output:str(out.str()) error:str(err.str()) data:changed];
}

@end
