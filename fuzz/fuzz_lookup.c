/*
 * libFuzzer target for the lookup code both modules share. The fuzzer input
 * is a MaxMind database file. The target opens it and looks up IPv4 and IPv6
 * addresses at several paths, with and without URI escaping, as the geoip2
 * variables do, and reads the metadata values. Built by fuzz/build.sh.
 */

#include <ngx_config.h>
#include <ngx_core.h>

#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

#pragma GCC diagnostic ignored "-Wunused-function"
#include "../ngx_geoip2_common.h"


static ngx_log_t        fuzz_log;
static ngx_open_file_t  fuzz_log_file;

/* Paths the tests and typical configurations use, one of each data type. */
static const char *fuzz_paths[][5] = {
    { "country", "iso_code", NULL },
    { "country", "names", "en", NULL },
    { "city", "names", "en", NULL },
    { "location", "latitude", NULL },
    { "location", "longitude", NULL },
    { "location", "accuracy_radius", NULL },
    { "subdivisions", "0", "iso_code", NULL },
    { "autonomous_system_number", NULL },
    { "is_in_european_union", NULL },
    { "uint128", NULL },
    { "double", NULL },
    { "bytes", NULL },
};

static const char *fuzz_ipv4[] = {
    "203.0.113.10", "81.2.69.160", "1.2.3.4", "10.0.5.1", "0.0.0.0",
};

static const char *fuzz_ipv6[] = {
    "2001:db8::1", "2a02:ffc0::", "::1", "::ffff:1.2.3.4",
};


int
LLVMFuzzerInitialize(int *argc, char ***argv)
{
    ngx_pagesize = getpagesize();
    ngx_cacheline_size = NGX_CPU_CACHE_LINE;
    for (ngx_pagesize_shift = 0; (ngx_pagesize >> ngx_pagesize_shift) > 1;
         ngx_pagesize_shift++) { /* void */ }

    fuzz_log_file.fd = ngx_stderr;
    fuzz_log.file = &fuzz_log_file;
    fuzz_log.log_level = NGX_LOG_EMERG;

    ngx_time_init();

    return 0;
}


static void
fuzz_lookups(ngx_pool_t *pool, ngx_geoip2_db_t *database,
    struct sockaddr *sockaddr)
{
    ngx_str_t   value;
    ngx_uint_t  i, escape;

    for (i = 0; i < sizeof(fuzz_paths) / sizeof(fuzz_paths[0]); i++) {
        for (escape = 0; escape < 2; escape++) {
            (void) ngx_geoip2_lookup(pool, database, sockaddr, fuzz_paths[i],
                                     escape, &value);
        }
    }
}


int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    int                    fd;
    char                   path[] = "/tmp/fuzz-mmdb-XXXXXX";
    ngx_str_t              value;
    ngx_uint_t             i;
    ngx_pool_t            *pool;
    ngx_geoip2_db_t        database;
    struct sockaddr_in     sin;
    struct sockaddr_in6    sin6;
    ngx_geoip2_metadata_t  metadata;

    fd = mkstemp(path);
    if (fd == -1) {
        return 0;
    }

    if (write(fd, data, size) != (ssize_t) size) {
        close(fd);
        unlink(path);
        return 0;
    }

    close(fd);

    ngx_memzero(&database, sizeof(ngx_geoip2_db_t));

    if (MMDB_open(path, MMDB_MODE_MMAP, &database.mmdb) != MMDB_SUCCESS) {
        unlink(path);
        return 0;
    }

    pool = ngx_create_pool(4096, &fuzz_log);
    if (pool == NULL) {
        MMDB_close(&database.mmdb);
        unlink(path);
        return 0;
    }

    ngx_memzero(&sin, sizeof(struct sockaddr_in));
    sin.sin_family = AF_INET;

    for (i = 0; i < sizeof(fuzz_ipv4) / sizeof(fuzz_ipv4[0]); i++) {
        if (inet_pton(AF_INET, fuzz_ipv4[i], &sin.sin_addr) == 1) {
            fuzz_lookups(pool, &database, (struct sockaddr *) &sin);
        }
    }

    ngx_memzero(&sin6, sizeof(struct sockaddr_in6));
    sin6.sin6_family = AF_INET6;

    for (i = 0; i < sizeof(fuzz_ipv6) / sizeof(fuzz_ipv6[0]); i++) {
        if (inet_pton(AF_INET6, fuzz_ipv6[i], &sin6.sin6_addr) == 1) {
            fuzz_lookups(pool, &database, (struct sockaddr *) &sin6);
        }
    }

    metadata.database = &database;

    for (metadata.field = NGX_GEOIP2_BUILD_EPOCH;
         metadata.field <= NGX_GEOIP2_LAST_CHANGE;
         metadata.field++)
    {
        (void) ngx_geoip2_metadata_value(pool, &metadata, &value);
    }

    ngx_destroy_pool(pool);
    MMDB_close(&database.mmdb);
    unlink(path);

    return 0;
}
