module [ReadErr, WriteErr, write, writeUtf8, writeBytes, readUtf8, readBytes, delete, writeErrToStr, readErrToStr]

import InternalFile
import PlatformTasks
import Path exposing [Path]
import InternalPath

## Tag union of possible errors when reading a file or directory.
ReadErr : InternalFile.ReadErr

## Tag union of possible errors when writing a file or directory.
WriteErr : InternalFile.WriteErr

## Write data to a file.
##
## First encode a `val` using a given `fmt` which implements the ability [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
##
## For example, suppose you have a `Json.toCompactUtf8` which implements
## [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
## You can use this to write [JSON](https://en.wikipedia.org/wiki/JSON)
## data to a file like this:
##
## ```
## # Writes `{"some":"json stuff"}` to the file `output.json`:
## File.write
##     { some: "json stuff" }
##     (Path.fromStr "output.json")
##     Json.toCompactUtf8
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
write : val, Path, fmt -> Task {} [FileWriteErr Path WriteErr] where val implements Encode.Encoding, fmt implements Encode.EncoderFormatting
write = \val, path, fmt ->
    bytes = Encode.toBytes val fmt

    # TODO handle encoding errors here, once they exist
    writeBytes bytes path

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.writeBytes [1, 2, 3] (Path.fromStr "myfile.dat")
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write] instead.
writeBytes : List U8, Path -> Task {} [FileWriteErr Path WriteErr]
writeBytes = \bytes, path ->
    toWriteTask path \pathBytes -> PlatformTasks.fileWriteBytes pathBytes bytes

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## File.writeUtf8 "Hello!" (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
writeUtf8 : Str, Path -> Task {} [FileWriteErr Path WriteErr]
writeUtf8 = \str, path ->
    toWriteTask path \bytes -> PlatformTasks.fileWriteUtf8 bytes str

## Deletes a file from the filesystem.
##
## Performs a [`DeleteFile`](https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-deletefile)
## on Windows and [`unlink`](https://en.wikipedia.org/wiki/Unlink_(Unix)) on
## UNIX systems. On Windows, this will fail when attempting to delete a readonly
## file; the file's readonly permission must be disabled before it can be
## successfully deleted.
##
## ```
## # Deletes the file named
## File.delete (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
##
delete : Path -> Task {} [FileWriteErr Path WriteErr]
delete = \path ->
    toWriteTask path \bytes -> PlatformTasks.fileDelete bytes

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## File.readBytes (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file, you can use `File.read` instead.
readBytes : Path -> Task (List U8) [FileReadErr Path ReadErr]
readBytes = \path ->
    toReadTask path \bytes -> PlatformTasks.fileReadBytes bytes

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## File.readUtf8 (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after writing to it.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [File.readBytes] instead.
readUtf8 : Path -> Task Str [FileReadErr Path ReadErr, FileReadUtf8Err Path]
readUtf8 = \path ->
    when PlatformTasks.fileReadBytes (InternalPath.toBytes path) |> Task.map Str.fromUtf8 |> Task.result! is
        Ok (Ok str) -> Task.ok str
        Ok (Err _) -> Task.err (FileReadUtf8Err path)
        Err readErr -> Task.err (FileReadErr path readErr)

toWriteTask : Path, (List U8 -> Task ok err) -> Task ok [FileWriteErr Path err]
toWriteTask = \path, toTask ->
    InternalPath.toBytes path
    |> toTask
    |> Task.mapErr \err -> FileWriteErr path err

toReadTask : Path, (List U8 -> Task ok err) -> Task ok [FileReadErr Path err]
toReadTask = \path, toTask ->
    InternalPath.toBytes path
    |> toTask
    |> Task.mapErr \err -> FileReadErr path err

## Converts a [WriteErr] to a [Str].
writeErrToStr : WriteErr -> Str
writeErrToStr = \err ->
    when err is
        NotFound -> "NotFound"
        Interrupted -> "Interrupted"
        InvalidFilename -> "InvalidFilename"
        PermissionDenied -> "PermissionDenied"
        TooManySymlinks -> "TooManySymlinks"
        TooManyHardlinks -> "TooManyHardlinks"
        TimedOut -> "TimedOut"
        StaleNetworkFileHandle -> "StaleNetworkFileHandle"
        ReadOnlyFilesystem -> "ReadOnlyFilesystem"
        AlreadyExists -> "AlreadyExists"
        WasADirectory -> "WasADirectory"
        WriteZero -> "WriteZero"
        StorageFull -> "StorageFull"
        FilesystemQuotaExceeded -> "FilesystemQuotaExceeded"
        FileTooLarge -> "FileTooLarge"
        ResourceBusy -> "ResourceBusy"
        ExecutableFileBusy -> "ExecutableFileBusy"
        OutOfMemory -> "OutOfMemory"
        Unsupported -> "Unsupported"
        _ -> "Unrecognized"

## Converts a [ReadErr] to a [Str].
readErrToStr : ReadErr -> Str
readErrToStr = \err ->
    when err is
        NotFound -> "NotFound"
        Interrupted -> "Interrupted"
        InvalidFilename -> "InvalidFilename"
        PermissionDenied -> "PermissionDenied"
        TooManySymlinks -> "TooManySymlinks"
        TooManyHardlinks -> "TooManyHardlinks"
        TimedOut -> "TimedOut"
        StaleNetworkFileHandle -> "StaleNetworkFileHandle"
        OutOfMemory -> "OutOfMemory"
        Unsupported -> "Unsupported"
        _ -> "Unrecognized"
