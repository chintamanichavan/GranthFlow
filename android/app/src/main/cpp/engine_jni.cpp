// Kotlin's face of the C++ engine, as AFEngine.mm is Swift's. Strings cross as UTF-8 byte arrays,
// not jstring, because JNI's string calls use a modified UTF-8 that mangles characters outside the
// Basic Multilingual Plane. The work itself is in anyfile::detectKind and runOnBytes.
#include <jni.h>

#include <string>
#include <vector>

#include "core/engine.hpp"

namespace {

std::string bytes(JNIEnv *env, jbyteArray array) {
    const jsize n = env->GetArrayLength(array);
    std::string out(static_cast<size_t>(n), '\0');
    env->GetByteArrayRegion(array, 0, n, reinterpret_cast<jbyte *>(out.data()));
    return out;
}

jbyteArray array(JNIEnv *env, const std::string &s) {
    jbyteArray out = env->NewByteArray(static_cast<jsize>(s.size()));
    env->SetByteArrayRegion(out, 0, static_cast<jsize>(s.size()), reinterpret_cast<const jbyte *>(s.data()));
    return out;
}

}  // namespace

extern "C" JNIEXPORT jbyteArray JNICALL
Java_local_granthflow_Engine_nativeDetectKind(JNIEnv *env, jobject, jbyteArray data, jbyteArray name) {
    return array(env, anyfile::detectKind(bytes(env, data), bytes(env, name)));
}

/// Returns { status as one byte, output, error, the file's new bytes or null }.
extern "C" JNIEXPORT jobjectArray JNICALL
Java_local_granthflow_Engine_nativeRun(JNIEnv *env, jobject, jbyteArray command, jobjectArray args, jbyteArray data,
                                       jbyteArray name, jbyteArray kind) {
    std::vector<std::string> argv;
    const jsize count = env->GetArrayLength(args);
    argv.reserve(static_cast<size_t>(count));
    for (jsize i = 0; i < count; ++i) {
        auto arg = static_cast<jbyteArray>(env->GetObjectArrayElement(args, i));
        argv.push_back(bytes(env, arg));
        env->DeleteLocalRef(arg);
    }
    const anyfile::RunResult r =
        anyfile::runOnBytes(bytes(env, command), argv, bytes(env, data), bytes(env, name), bytes(env, kind));

    jobjectArray out = env->NewObjectArray(4, env->FindClass("[B"), nullptr);
    env->SetObjectArrayElement(out, 0, array(env, std::string(1, static_cast<char>(r.status))));
    env->SetObjectArrayElement(out, 1, array(env, r.output));
    env->SetObjectArrayElement(out, 2, array(env, r.error));
    if (r.didChange) env->SetObjectArrayElement(out, 3, array(env, r.changed));
    return out;
}
