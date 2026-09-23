/*
 * Copyright (C) Lee Valentine <lee@leev.net>
 * Copyright (C) Andrei Belov <defanator@gmail.com>
 *
 * Based on nginx's 'ngx_http_geoip_module.c' and 'ngx_stream_geoip_module.c'
 * by Igor Sysoev
 *
 * The database code of the http and the stream module. Every function is
 * static, so each module holds its own copy and no symbols clash.
 */


#ifndef _NGX_GEOIP2_COMMON_H_INCLUDED_
#define _NGX_GEOIP2_COMMON_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>

#include <maxminddb.h>


/*
 * GCOVR_EXCL marks code the tests cannot reach: allocation failures and
 * errors that valid input never triggers. tests/coverage.sh also excludes
 * the branches inside the NGX_GEOIP2_FORMAT and ngx_log_error macros.
 */


typedef struct {
    MMDB_s                   mmdb;
    MMDB_lookup_result_s     result;
    time_t                   last_check;
    time_t                   last_change;
    time_t                   check_interval;
    ngx_file_uniq_t          file_uniq;
    off_t                    file_size;
#if (NGX_HAVE_INET6)
    uint8_t                  address[16];
#else
    unsigned long            address;
#endif
    ngx_queue_t              queue;
} ngx_geoip2_db_t;

typedef struct {
    ngx_geoip2_db_t          *database;
    ngx_uint_t               field;
} ngx_geoip2_metadata_t;

#define NGX_GEOIP2_BUILD_EPOCH  0
#define NGX_GEOIP2_LAST_CHECK   1
#define NGX_GEOIP2_LAST_CHANGE  2


/* the longest value is a uint128 in hex: "0x" and 32 digits */
#define NGX_GEOIP2_VALUE_LEN  64

#define NGX_GEOIP2_FORMAT(fmt, ...) do {                                \
        p = ngx_palloc(pool, NGX_GEOIP2_VALUE_LEN);                     \
        if (p == NULL) {                                                \
            return NGX_ERROR;                                           \
        }                                                               \
        value->len = ngx_snprintf(p, NGX_GEOIP2_VALUE_LEN, fmt,         \
                                  __VA_ARGS__) - p;                     \
        value->data = p;                                                \
} while (0)


/*
 * Opens the database of a geoip2 block: the file in its argument. Rejects a
 * file the list of databases already holds.
 */
static char *
ngx_geoip2_open(ngx_conf_t *cf, ngx_queue_t *databases,
    ngx_geoip2_db_t **database)
{
    int               status;
    ngx_str_t        *value;
    ngx_queue_t      *q;
    ngx_file_info_t   fi;
    ngx_geoip2_db_t  *db;

    value = cf->args->elts;

    if (value[1].data[0] != '/') {
        if (ngx_conf_full_name(cf->cycle, &value[1], 0) != NGX_OK) {  /* GCOVR_EXCL_BR_LINE */
            return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
        }
    }

    for (q = ngx_queue_head(databases);
         q != ngx_queue_sentinel(databases);
         q = ngx_queue_next(q))
    {
        db = ngx_queue_data(q, ngx_geoip2_db_t, queue);
        if (ngx_strcmp(value[1].data, db->mmdb.filename) == 0) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "Duplicate GeoIP2 mmdb - %V", &value[1]);
            return NGX_CONF_ERROR;
        }
    }

    db = ngx_pcalloc(cf->pool, sizeof(ngx_geoip2_db_t));
    if (db == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    /* the cleanup closes the database, also after a failed MMDB_open */
    ngx_queue_insert_tail(databases, &db->queue);
    db->last_check = db->last_change = ngx_time();

    status = MMDB_open((char *) value[1].data, MMDB_MODE_MMAP, &db->mmdb);

    if (status != MMDB_SUCCESS) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "MMDB_open(\"%V\") failed - %s", &value[1],
                           MMDB_strerror(status));
        return NGX_CONF_ERROR;
    }

    if (ngx_file_info(db->mmdb.filename, &fi) != NGX_FILE_ERROR) {  /* GCOVR_EXCL_BR_LINE */
        db->file_uniq = ngx_file_uniq(&fi);
        db->file_size = ngx_file_size(&fi);
    }

    *database = db;

    return NGX_CONF_OK;
}


/* A setting in a geoip2 block other than a variable: auto_reload. */
static char *
ngx_geoip2_setting(ngx_conf_t *cf, ngx_geoip2_db_t *database)
{
    time_t      interval;
    ngx_str_t  *value;

    value = cf->args->elts;

    if (value[0].len == 11
            && ngx_strncmp(value[0].data, "auto_reload", 11) == 0) {
        if ((int) cf->args->nelts != 2) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid number of arguments for auto_reload");
            return NGX_CONF_ERROR;
        }

        interval = ngx_parse_time(&value[1], true);

        if (interval == (time_t) NGX_ERROR) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid interval for auto_reload \"%V\"",
                               &value[1]);
            return NGX_CONF_ERROR;
        }

        database->check_interval = interval;
        return NGX_CONF_OK;
    }

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "invalid setting \"%V\"", &value[0]);
    return NGX_CONF_ERROR;
}


/* Returns 1 for "$name metadata <field>", the arguments without the '$'. */
static ngx_uint_t
ngx_geoip2_is_metadata(ngx_conf_t *cf)
{
    ngx_str_t  *value;

    value = cf->args->elts;

    return cf->args->nelts > 1 && value[1].len == 8
           && ngx_strncmp(value[1].data, "metadata", 8) == 0;
}


/* Parses "$name metadata <field>" into a new metadata variable. */
static char *
ngx_geoip2_metadata(ngx_conf_t *cf, ngx_geoip2_db_t *database,
    ngx_geoip2_metadata_t **metadata)
{
    ngx_str_t              *value;
    ngx_geoip2_metadata_t  *md;

    value = cf->args->elts;

    if (cf->args->nelts != 3) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid number of arguments for metadata \"$%V\"",
                           &value[0]);
        return NGX_CONF_ERROR;
    }

    md = ngx_pcalloc(cf->pool, sizeof(ngx_geoip2_metadata_t));
    if (md == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    if (ngx_strcmp(value[2].data, "build_epoch") == 0) {
        md->field = NGX_GEOIP2_BUILD_EPOCH;
    } else if (ngx_strcmp(value[2].data, "last_check") == 0) {
        md->field = NGX_GEOIP2_LAST_CHECK;
    } else if (ngx_strcmp(value[2].data, "last_change") == 0) {
        md->field = NGX_GEOIP2_LAST_CHANGE;
    } else {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid metadata field \"%V\" for \"$%V\"",
                           &value[2], &value[0]);
        return NGX_CONF_ERROR;
    }

    md->database = database;
    *metadata = md;

    return NGX_CONF_OK;
}


/*
 * Parses "$name [default=<value>] [source=$variable] path ...". Sets the
 * default value and the source, and returns the lookup path.
 */
static char *
ngx_geoip2_variable(ngx_conf_t *cf, ngx_str_t *default_value,
    ngx_str_t *source, const char ***lookup)
{
    ngx_str_t     *value, *arg;
    ngx_uint_t     i, idx;
    const char   **path;

    value = cf->args->elts;

    ngx_str_null(default_value);
    ngx_str_null(source);

    for (idx = 1; idx < cf->args->nelts; idx++) {
        arg = &value[idx];

        if (ngx_strnstr(arg->data, "=", arg->len) == NULL) {
            break;
        }

        if (arg->len > 8 && ngx_strncmp(arg->data, "default=", 8) == 0) {
            if (default_value->len > 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "default has already been declared for  \"$%V\"",
                                   &value[0]);
                return NGX_CONF_ERROR;
            }

            default_value->len = arg->len - 8;
            default_value->data = arg->data + 8;

        } else if (arg->len > 7 && ngx_strncmp(arg->data, "source=", 7) == 0) {
            if (source->len > 0) {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "source has already been declared for  \"$%V\"",
                                   &value[0]);
                return NGX_CONF_ERROR;
            }

            source->len = arg->len - 7;
            source->data = arg->data + 7;

            if (source->data[0] != '$') {
                ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                                   "invalid source variable name \"%V\"",
                                   source);
                return NGX_CONF_ERROR;
            }

        } else {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid setting \"%V\" for \"$%V\"",
                               arg, &value[0]);
            return NGX_CONF_ERROR;
        }
    }

    path = ngx_pcalloc(cf->pool,
                       sizeof(const char *) * (cf->args->nelts - idx + 1));
    if (path == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    for (i = 0; idx + i < cf->args->nelts; i++) {
        path[i] = (char *) value[idx + i].data;
    }

    *lookup = path;

    return NGX_CONF_OK;
}


/*
 * Looks up the address and writes the data at the path to value. Returns
 * NGX_DECLINED when the database holds no usable value there. The database
 * caches the result of the last address.
 */
static ngx_int_t
ngx_geoip2_lookup(ngx_pool_t *pool, ngx_geoip2_db_t *database,
    struct sockaddr *sockaddr, const char **path, ngx_str_t *value)
{
    int                 mmdb_error;
    u_char             *p;
    MMDB_entry_data_s   entry_data;
#if (NGX_HAVE_INET6)
    uint8_t             address[16], *addressp = address;
#else
    unsigned long       address;
#endif

    switch (sockaddr->sa_family) {
        case AF_INET:
#if (NGX_HAVE_INET6)
            ngx_memset(addressp, 0, 12);
            ngx_memcpy(addressp + 12, &((struct sockaddr_in *)
                                        sockaddr)->sin_addr.s_addr, 4);
            break;

        case AF_INET6:
            ngx_memcpy(addressp, &((struct sockaddr_in6 *)
                                   sockaddr)->sin6_addr.s6_addr, 16);
#else
            address = ((struct sockaddr_in *) sockaddr)->sin_addr.s_addr;
#endif
            break;

        default:
            return NGX_DECLINED;
    }

#if (NGX_HAVE_INET6)
    if (ngx_memcmp(&address, &database->address, sizeof(address)) != 0) {
#else
    if (address != database->address) {
#endif
        ngx_memcpy(&database->address, &address, sizeof(address));
        database->result = MMDB_lookup_sockaddr(&database->mmdb, sockaddr,
                                                &mmdb_error);

        if (mmdb_error != MMDB_SUCCESS) {
            return NGX_DECLINED;
        }
    }

    if (!database->result.found_entry
        || MMDB_aget_value(&database->result.entry, &entry_data, path)
           != MMDB_SUCCESS)
    {
        return NGX_DECLINED;
    }

    /* older libmaxminddb versions report a missing key this way */
    if (!entry_data.has_data) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_DECLINED;  /* GCOVR_EXCL_LINE */
    }

    switch (entry_data.type) {
        case MMDB_DATA_TYPE_BOOLEAN:
            NGX_GEOIP2_FORMAT("%d", entry_data.boolean);
            break;
        case MMDB_DATA_TYPE_UTF8_STRING:
            value->len = entry_data.data_size;
            value->data = ngx_pnalloc(pool, value->len);
            if (value->data == NULL) {  /* GCOVR_EXCL_BR_LINE */
                return NGX_ERROR;  /* GCOVR_EXCL_LINE */
            }
            ngx_memcpy(value->data, entry_data.utf8_string, value->len);
            break;
        case MMDB_DATA_TYPE_BYTES:
            value->len = entry_data.data_size;
            value->data = ngx_pnalloc(pool, value->len);
            if (value->data == NULL) {  /* GCOVR_EXCL_BR_LINE */
                return NGX_ERROR;  /* GCOVR_EXCL_LINE */
            }
            ngx_memcpy(value->data, entry_data.bytes, value->len);
            break;
        case MMDB_DATA_TYPE_FLOAT:
            NGX_GEOIP2_FORMAT("%.5f", entry_data.float_value);
            break;
        case MMDB_DATA_TYPE_DOUBLE:
            NGX_GEOIP2_FORMAT("%.5f", entry_data.double_value);
            break;
        case MMDB_DATA_TYPE_UINT16:
            NGX_GEOIP2_FORMAT("%uD", entry_data.uint16);
            break;
        case MMDB_DATA_TYPE_UINT32:
            NGX_GEOIP2_FORMAT("%uD", entry_data.uint32);
            break;
        case MMDB_DATA_TYPE_INT32:
            NGX_GEOIP2_FORMAT("%D", entry_data.int32);
            break;
        case MMDB_DATA_TYPE_UINT64:
            NGX_GEOIP2_FORMAT("%uL", entry_data.uint64);
            break;
        case MMDB_DATA_TYPE_UINT128: ;
#if MMDB_UINT128_IS_BYTE_ARRAY
            uint8_t *val = (uint8_t *) entry_data.uint128;
            NGX_GEOIP2_FORMAT("0x%02x%02x%02x%02x%02x%02x%02x%02x"
                              "%02x%02x%02x%02x%02x%02x%02x%02x",
                              val[0], val[1], val[2], val[3],
                              val[4], val[5], val[6], val[7],
                              val[8], val[9], val[10], val[11],
                              val[12], val[13], val[14], val[15]);
#else
            mmdb_uint128_t val = entry_data.uint128;
            NGX_GEOIP2_FORMAT("0x%016uxL%016uxL",
                              (uint64_t) (val >> 64), (uint64_t) val);
#endif
            break;
        default:
            return NGX_DECLINED;
    }

    return NGX_OK;
}


/* Writes the value of a metadata variable. */
static ngx_int_t
ngx_geoip2_metadata_value(ngx_pool_t *pool, ngx_geoip2_metadata_t *metadata,
    ngx_str_t *value)
{
    u_char           *p;
    ngx_geoip2_db_t  *database = metadata->database;

    switch (metadata->field) {
        case NGX_GEOIP2_BUILD_EPOCH:
            NGX_GEOIP2_FORMAT("%uL", database->mmdb.metadata.build_epoch);
            break;
        case NGX_GEOIP2_LAST_CHECK:
            NGX_GEOIP2_FORMAT("%T", database->last_check);
            break;
        default: /* NGX_GEOIP2_LAST_CHANGE */
            NGX_GEOIP2_FORMAT("%T", database->last_change);
            break;
    }

    return NGX_OK;
}


/*
 * Reloads each database whose auto_reload interval has passed and whose file
 * has changed: a newer mtime, another inode or another size.
 */
static void
ngx_geoip2_reload(ngx_queue_t *databases, ngx_log_t *log)
{
    int               status;
    MMDB_s            tmpdb;
    ngx_queue_t      *q;
    ngx_file_info_t   fi;
    ngx_geoip2_db_t  *database;

    for (q = ngx_queue_head(databases);
         q != ngx_queue_sentinel(databases);
         q = ngx_queue_next(q))
    {
        database = ngx_queue_data(q, ngx_geoip2_db_t, queue);
        if (database->check_interval == 0) {
            continue;
        }

        if ((database->last_check + database->check_interval)
            > ngx_time())
        {
            continue;
        }

        database->last_check = ngx_time();

        if (ngx_file_info(database->mmdb.filename, &fi) == NGX_FILE_ERROR) {
            ngx_log_error(NGX_LOG_EMERG, log, ngx_errno,
                          ngx_file_info_n " \"%s\" failed",
                          database->mmdb.filename);

            continue;
        }

        if (ngx_file_mtime(&fi) <= database->last_change
            && ngx_file_uniq(&fi) == database->file_uniq
            && ngx_file_size(&fi) == database->file_size)
        {
            continue;
        }

        /* do the reload */

        ngx_memzero(&tmpdb, sizeof(MMDB_s));
        status = MMDB_open(database->mmdb.filename, MMDB_MODE_MMAP, &tmpdb);

        if (status != MMDB_SUCCESS) {
            ngx_log_error(NGX_LOG_ERR, log, 0,
                          "MMDB_open(\"%s\") failed to reload - %s",
                          database->mmdb.filename, MMDB_strerror(status));

            continue;
        }

        database->last_change = ngx_file_mtime(&fi);
        database->file_uniq = ngx_file_uniq(&fi);
        database->file_size = ngx_file_size(&fi);
        MMDB_close(&database->mmdb);
        database->mmdb = tmpdb;

        /* invalidate the cached lookup result from the old database */
        ngx_memzero(&database->address, sizeof(database->address));
        ngx_memzero(&database->result, sizeof(database->result));

        ngx_log_error(NGX_LOG_INFO, log, 0,
                      "Reload MMDB \"%s\"",
                      database->mmdb.filename);
    }
}


/* Pool cleanup: closes every database of the list in data. */
static void
ngx_geoip2_cleanup(void *data)
{
    ngx_queue_t      *databases = data;
    ngx_queue_t      *q;
    ngx_geoip2_db_t  *database;

    while (!ngx_queue_empty(databases)) {
        q = ngx_queue_head(databases);
        ngx_queue_remove(q);
        database = ngx_queue_data(q, ngx_geoip2_db_t, queue);
        MMDB_close(&database->mmdb);
    }
}


#endif /* _NGX_GEOIP2_COMMON_H_INCLUDED_ */
