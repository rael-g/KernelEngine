#ifndef KERNEL_ENGINE_IO_IO_H_
#define KERNEL_ENGINE_IO_IO_H_

#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** A read submitted to ke_io, released by the one ke_io.wait it is given to. */
    typedef struct ke_io_request ke_io_request;

    /** What ke_io.wait reports of a request; each field is filled by the requests named on it. */
    typedef struct ke_io_result
    {
        /** open: the file, released with ke_io.close. */
        ke_open_file *file;
        /** read_file: the file's bytes, owned by the caller and released with ke_io.free_bytes. */
        void *bytes;
        /** read_file: the number of bytes; read_at: the number of bytes read. */
        uint64_t size;
        /** stat: what the path names. */
        ke_file_stat stat;
        /** file_exists: whether the path names a regular file. */
        bool exists;
    } ke_io_result;

    /**
     * Reads files without blocking the caller: each slot that reads submits a request, which runs
     * elsewhere and is waited on exactly once. A request never waited on is never released. Paths
     * follow ke_file_system. Every slot may be called from several threads at once.
     */
    typedef struct ke_io
    {
        void *handle;

        /**
         * Submits a read of a whole file.
         * @param path [borrowed] The file to read; copied before the slot returns.
         * @param out_request [out] Receives the request; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_request,
         *         KE_RESULT_OUT_OF_MEMORY, or the code the task pool refused the request with.
         */
        ke_result (*read_file)(struct ke_io *self, const char *path, ke_io_request **out_request);

        /**
         * Submits the opening of a file for read_at.
         * @param path [borrowed] The file to open; copied before the slot returns.
         * @param out_request [out] Receives the request; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_request,
         *         KE_RESULT_OUT_OF_MEMORY, or the code the task pool refused the request with.
         */
        ke_result (*open)(struct ke_io *self, const char *path, ke_io_request **out_request);

        /**
         * Submits a read from an open file at an offset; it reads fewer than @p len bytes only at
         * the end of the file.
         * @param file [borrowed] A file an open request reported.
         * @param offset Where the read starts, in bytes from the start of the file.
         * @param dst [borrowed] Receives the bytes; the caller's until wait returns.
         * @param len The number of bytes @p dst holds.
         * @param out_request [out] Receives the request; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p file, a null @p dst with a
         *         non-zero @p len or a null @p out_request, KE_RESULT_OUT_OF_MEMORY, or the code
         *         the task pool refused the request with.
         */
        ke_result (*read_at)(struct ke_io *self, ke_open_file *file, uint64_t offset,
                             void *dst, size_t len, ke_io_request **out_request);

        /**
         * Submits an inspection of what a path names.
         * @param path [borrowed] The path to inspect; copied before the slot returns.
         * @param out_request [out] Receives the request; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_request,
         *         KE_RESULT_OUT_OF_MEMORY, or the code the task pool refused the request with.
         */
        ke_result (*stat)(struct ke_io *self, const char *path, ke_io_request **out_request);

        /**
         * Submits the question whether a path names a regular file; a path that names nothing,
         * or something else, is reported as no, not as a failure.
         * @param path [borrowed] The path to ask about; copied before the slot returns.
         * @param out_request [out] Receives the request; null on failure.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_request,
         *         KE_RESULT_OUT_OF_MEMORY, or the code the task pool refused the request with.
         */
        ke_result (*file_exists)(struct ke_io *self, const char *path, ke_io_request **out_request);

        /**
         * Reports whether a request has finished, without releasing it. Valid only before the
         * request is waited on.
         * @param request [borrowed] A request a submit slot returned.
         */
        bool (*is_completed)(struct ke_io *self, ke_io_request *request);

        /**
         * Blocks until the request finishes, releases it, and reports what it read.
         * @param request [borrowed] A request a submit slot returned; invalid afterwards.
         * @param out_result [out,optional] Receives what the request read; left zeroed when it
         *        failed.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p request, the code the task pool
         *         refused the wait with, the request then still to be waited on, or the failure of
         *         the read: KE_RESULT_NOT_FOUND, KE_RESULT_OUT_OF_MEMORY or KE_RESULT_IO.
         */
        ke_result (*wait)(struct ke_io *self, ke_io_request *request, ke_io_result *out_result);

        /**
         * Releases a file an open request reported; it is invalid afterwards. A null @p file is
         * ignored.
         * @param file [borrowed] The file to release.
         */
        void (*close)(struct ke_io *self, ke_open_file *file);

        /**
         * Releases the bytes a read_file request reported. Null @p bytes are ignored.
         * @param bytes [borrowed] The bytes to release.
         */
        void (*free_bytes)(struct ke_io *self, void *bytes);

    } ke_io;

    typedef struct ke_io_handle
    {
        ke_io *ref;
        void (*destroy)(ke_io *self);
    } ke_io_handle;

#ifdef __cplusplus
}
#endif

#endif
