// The C++ engine, as Engine.swift wraps it on Apple platforms: bytes in, a result out.
package local.granthflow

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

object Engine {
    init {
        System.loadLibrary("anyfile_jni")
    }

    class Result(val status: Int, val outputBytes: ByteArray, val error: String, val changed: ByteArray?) {
        val output: String by lazy { text(outputBytes) }
        val succeeded get() = status == 0
    }

    /** "pdf", "epub", "markdown", "text" or "binary". */
    fun detectKind(data: ByteArray, name: String): String = text(nativeDetectKind(data, name.toByteArray()))

    /** Runs one command on a file's bytes. `kind` may be empty to detect it. */
    fun run(command: String, args: List<String> = emptyList(), data: ByteArray, name: String, kind: String): Result {
        val r = nativeRun(command.toByteArray(), args.map { it.toByteArray() }.toTypedArray(), data, name.toByteArray(), kind.toByteArray())
        return Result(r[0]!![0].toInt(), r[1]!!, text(r[2]!!), r[3])
    }

    /** Engine output is UTF-8 unless a binary file leaks bytes into it; then Latin-1, so nothing is lost. */
    private fun text(bytes: ByteArray): String = try {
        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
    } catch (e: CharacterCodingException) {
        String(bytes, Charsets.ISO_8859_1)
    }

    private external fun nativeDetectKind(data: ByteArray, name: ByteArray): ByteArray
    private external fun nativeRun(command: ByteArray, args: Array<ByteArray>, data: ByteArray, name: ByteArray, kind: ByteArray): Array<ByteArray?>
}
