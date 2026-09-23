/*
 * Copyright (C) Lee Valentine <lee@leev.net>
 * Copyright (C) Andrei Belov <defanator@gmail.com>
 *
 * Based on nginx's 'ngx_stream_geoip_module.c' by Igor Sysoev
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>

#include "ngx_geoip2_common.h"


typedef struct {
    ngx_queue_t              databases;
} ngx_stream_geoip2_conf_t;

typedef struct {
    ngx_geoip2_db_t          *database;
    const char               **lookup;
    ngx_str_t                default_value;
    ngx_stream_complex_value_t source;
} ngx_stream_geoip2_ctx_t;


static ngx_int_t ngx_stream_geoip2_variable(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_stream_geoip2_metadata(ngx_stream_session_t *s,
    ngx_stream_variable_value_t *v, uintptr_t data);
static void *ngx_stream_geoip2_create_conf(ngx_conf_t *cf);
static char *ngx_stream_geoip2(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_stream_geoip2_parse_config(ngx_conf_t *cf, ngx_command_t *dummy,
    void *conf);
static char *ngx_stream_geoip2_add_variable(ngx_conf_t *cf,
    ngx_geoip2_db_t *database);
static ngx_int_t ngx_stream_geoip2_init(ngx_conf_t *cf);


static ngx_command_t  ngx_stream_geoip2_commands[] = {

    { ngx_string("geoip2"),
        NGX_STREAM_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_TAKE1,
        ngx_stream_geoip2,
        NGX_STREAM_MAIN_CONF_OFFSET,
        0,
        NULL },

    ngx_null_command
};


static ngx_stream_module_t  ngx_stream_geoip2_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_stream_geoip2_init,                /* postconfiguration */

    ngx_stream_geoip2_create_conf,         /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL                                   /* merge server configuration */
};


ngx_module_t  ngx_stream_geoip2_module = {
    NGX_MODULE_V1,
    &ngx_stream_geoip2_module_ctx,         /* module context */
    ngx_stream_geoip2_commands,            /* module directives */
    NGX_STREAM_MODULE,                     /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_stream_geoip2_variable(ngx_stream_session_t *s, ngx_stream_variable_value_t *v,
    uintptr_t data)
{
    ngx_int_t                 rc;
    ngx_str_t                 val;
    ngx_addr_t                addr;
    ngx_stream_geoip2_ctx_t  *geoip2 = (ngx_stream_geoip2_ctx_t *) data;

    if (geoip2->source.value.len > 0) {
        if (ngx_stream_complex_value(s, &geoip2->source, &val) != NGX_OK) {  /* GCOVR_EXCL_BR_LINE */
            goto not_found;  /* GCOVR_EXCL_LINE */
        }

        if (ngx_parse_addr(s->connection->pool, &addr, val.data, val.len) != NGX_OK) {
            goto not_found;
        }
    } else {
        addr.sockaddr = s->connection->sockaddr;
        addr.socklen = s->connection->socklen;
    }

    rc = ngx_geoip2_lookup(s->connection->pool, geoip2->database,
                           addr.sockaddr, geoip2->lookup, &val);

    if (rc == NGX_ERROR) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_ERROR;  /* GCOVR_EXCL_LINE */
    }

    if (rc == NGX_DECLINED) {
        goto not_found;
    }

    v->data = val.data;
    v->len = val.len;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    return NGX_OK;

not_found:
    if (geoip2->default_value.len > 0) {
        v->data = geoip2->default_value.data;
        v->len = geoip2->default_value.len;

        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;

        return NGX_OK;
    }

    v->not_found = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_stream_geoip2_metadata(ngx_stream_session_t *s, ngx_stream_variable_value_t *v,
    uintptr_t data)
{
    ngx_int_t  rc;
    ngx_str_t  val;

    rc = ngx_geoip2_metadata_value(s->connection->pool,
                                   (ngx_geoip2_metadata_t *) data, &val);
    if (rc != NGX_OK) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_ERROR;  /* GCOVR_EXCL_LINE */
    }

    v->data = val.data;
    v->len = val.len;

    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    return NGX_OK;
}


static void *
ngx_stream_geoip2_create_conf(ngx_conf_t *cf)
{
    ngx_pool_cleanup_t        *cln;
    ngx_stream_geoip2_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_stream_geoip2_conf_t));
    if (conf == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NULL;  /* GCOVR_EXCL_LINE */
    }

    cln = ngx_pool_cleanup_add(cf->pool, 0);
    if (cln == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NULL;  /* GCOVR_EXCL_LINE */
    }

    ngx_queue_init(&conf->databases);

    cln->handler = ngx_geoip2_cleanup;
    cln->data = &conf->databases;

    return conf;
}


static char *
ngx_stream_geoip2(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    char                      *rv;
    ngx_conf_t                save;
    ngx_geoip2_db_t           *database;
    ngx_stream_geoip2_conf_t  *gcf = conf;

    rv = ngx_geoip2_open(cf, &gcf->databases, &database);
    if (rv != NGX_CONF_OK) {
        return rv;
    }

    save = *cf;
    cf->handler = ngx_stream_geoip2_parse_config;
    cf->handler_conf = (void *) database;

    rv = ngx_conf_parse(cf, NULL);
    *cf = save;
    return rv;
}


static char *
ngx_stream_geoip2_parse_config(ngx_conf_t *cf, ngx_command_t *dummy, void *conf)
{
    ngx_str_t  *value;

    value = cf->args->elts;

    if (value[0].data[0] == '$') {
        return ngx_stream_geoip2_add_variable(cf, conf);
    }

    return ngx_geoip2_setting(cf, conf);
}


static char *
ngx_stream_geoip2_add_variable(ngx_conf_t *cf, ngx_geoip2_db_t *database)
{
    char                                *rv;
    ngx_str_t                           *value, source;
    ngx_stream_variable_t               *var;
    ngx_geoip2_metadata_t               *metadata;
    ngx_stream_geoip2_ctx_t             *geoip2;
    ngx_stream_compile_complex_value_t  ccv;

    value = cf->args->elts;

    /* ngx_stream_geoip2_parse_config calls this only for a name with a '$' */
    value[0].len--;
    value[0].data++;

    if (ngx_geoip2_is_metadata(cf)) {
        rv = ngx_geoip2_metadata(cf, database, &metadata);
        if (rv != NGX_CONF_OK) {
            return rv;
        }

        var = ngx_stream_add_variable(cf, &value[0], NGX_STREAM_VAR_CHANGEABLE);
        if (var == NULL) {
            return NGX_CONF_ERROR;
        }

        var->get_handler = ngx_stream_geoip2_metadata;
        var->data = (uintptr_t) metadata;

        return NGX_CONF_OK;
    }

    geoip2 = ngx_pcalloc(cf->pool, sizeof(ngx_stream_geoip2_ctx_t));
    if (geoip2 == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    geoip2->database = database;

    rv = ngx_geoip2_variable(cf, &geoip2->default_value, &source,
                             &geoip2->lookup);
    if (rv != NGX_CONF_OK) {
        return rv;
    }

    if (source.len > 0) {
        ngx_memzero(&ccv, sizeof(ngx_stream_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &source;
        ccv.complex_value = &geoip2->source;

        if (ngx_stream_compile_complex_value(&ccv) != NGX_OK) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "unable to compile \"%V\" for \"$%V\"",
                               &source, &value[0]);
            return NGX_CONF_ERROR;
        }
    }

    var = ngx_stream_add_variable(cf, &value[0], NGX_STREAM_VAR_CHANGEABLE);
    if (var == NULL) {
        return NGX_CONF_ERROR;
    }

    var->get_handler = ngx_stream_geoip2_variable;
    var->data = (uintptr_t) geoip2;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_stream_geoip2_log_handler(ngx_stream_session_t *s)
{
    ngx_stream_geoip2_conf_t  *gcf;

    ngx_log_debug0(NGX_LOG_DEBUG_STREAM, s->connection->log, 0,
                   "geoip2 stream log handler");

    gcf = ngx_stream_get_module_main_conf(s, ngx_stream_geoip2_module);

    ngx_geoip2_reload(&gcf->databases, s->connection->log);

    return NGX_OK;
}


static ngx_int_t
ngx_stream_geoip2_init(ngx_conf_t *cf)
{
    ngx_stream_handler_pt        *h;
    ngx_stream_core_main_conf_t  *cmcf;

    cmcf = ngx_stream_conf_get_module_main_conf(cf, ngx_stream_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_STREAM_LOG_PHASE].handlers);
    if (h == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_ERROR;  /* GCOVR_EXCL_LINE */
    }

    *h = ngx_stream_geoip2_log_handler;

    return NGX_OK;
}
