#ifndef KERNEL_ENGINE_FILE_SYSTEM_FILE_SYSTEM_H_
#define KERNEL_ENGINE_FILE_SYSTEM_FILE_SYSTEM_H_

#include <kernel_engine/result/result.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** A file ke_file_system.open opened, read through its slots until ke_file_system.close. */
    typedef struct ke_open_file ke_open_file;

    /** What a path names. */
    typedef enum ke_file_kind
    {
        KE_FILE_KIND_FILE      = 1,
        KE_FILE_KIND_DIRECTORY = 2,
        KE_FILE_KIND_OTHER     = 3,
    } ke_file_kind;

    /** What ke_file_system.stat reports about a path. */
    typedef struct ke_file_stat
    {
        /** What the path names. */
        ke_file_kind kind;
        /** Its size in bytes; meaningful for a file only. */
        uint64_t size;
    } ke_file_stat;

    /**
     * Read-only access to the files of one platform. Paths are UTF-8 with '/' as the separator; a
     * relative path is resolved against the root the implementation was created with. Every slot
     * may be called from several threads at once, read_at on one open file included.
     */
    typedef struct ke_file_system
    {
        void *handle;

        /**
         * Opens a file for reading.
         * @param path [borrowed] The file to open.
         * @param out_file [out] Receives the open file, released by close; left null on failure.
         * @return KE_OK, KE_RESULT_NOT_FOUND for a path that names nothing,
         *         KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_file, KE_RESULT_OUT_OF_MEMORY, or KE_RESULT_IO.
         */
        ke_result (*open)(struct ke_file_system *self, const char *path, ke_open_file **out_file);

        /**
         * Reports the size of an open file.
         * @param file [borrowed] A file open was given.
         * @param out_size [out] Receives the size in bytes.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p file or @p out_size, or
         *         KE_RESULT_IO.
         */
        ke_result (*size)(struct ke_file_system *self, ke_open_file *file, uint64_t *out_size);

        /**
         * Reads from an open file at an offset, leaving no position behind, so reads of one file
         * from several threads do not interfere.
         * @param file [borrowed] A file open was given.
         * @param offset Where the read starts, in bytes from the start of the file.
         * @param dst [borrowed] Receives the bytes.
         * @param len The number of bytes @p dst holds.
         * @param out_read [out] Receives the number of bytes read, fewer than @p len only at the
         *        end of the file.
         * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p file, @p out_read, or @p dst
         *         with a non-zero @p len, or KE_RESULT_IO.
         */
        ke_result (*read_at)(struct ke_file_system *self, ke_open_file *file, uint64_t offset,
                             void *dst, size_t len, size_t *out_read);

        /**
         * Releases an open file; it is invalid afterwards. A null @p file is ignored.
         * @param file [borrowed] A file open was given.
         */
        void (*close)(struct ke_file_system *self, ke_open_file *file);

        /**
         * Reports what a path names without opening it.
         * @param path [borrowed] The path to inspect.
         * @param out_stat [out] Receives what the path names.
         * @return KE_OK, KE_RESULT_NOT_FOUND for a path that names nothing,
         *         KE_RESULT_INVALID_ARGUMENT for a null @p path or @p out_stat, or KE_RESULT_IO.
         */
        ke_result (*stat)(struct ke_file_system *self, const char *path, ke_file_stat *out_stat);

    } ke_file_system;

    /// [owner]
    typedef struct ke_file_system_handle
    {
        ke_file_system *ref;
        void (*destroy)(ke_file_system *self);
    } ke_file_system_handle;

#ifdef __cplusplus
}
#endif

#endif
