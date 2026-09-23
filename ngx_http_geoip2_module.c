/*
 * Copyright (C) Lee Valentine <lee@leev.net>
 *
 * Based on nginx's 'ngx_http_geoip_module.c' by Igor Sysoev
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include "ngx_geoip2_common.h"


typedef struct {
    ngx_queue_t              databases;
    ngx_array_t              *proxies;
    ngx_flag_t               proxy_recursive;
} ngx_http_geoip2_conf_t;

typedef struct {
    ngx_geoip2_db_t          *database;
    const char               **lookup;
    ngx_str_t                default_value;
    ngx_uint_t               escape;
    ngx_http_complex_value_t source;
} ngx_http_geoip2_ctx_t;


static ngx_int_t ngx_http_geoip2_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_geoip2_metadata(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static void *ngx_http_geoip2_create_conf(ngx_conf_t *cf);
static char *ngx_http_geoip2_init_conf(ngx_conf_t *cf, void *conf);
static char *ngx_http_geoip2(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_geoip2_parse_config(ngx_conf_t *cf, ngx_command_t *dummy,
    void *conf);
static char *ngx_http_geoip2_add_variable(ngx_conf_t *cf,
    ngx_geoip2_db_t *database);
static ngx_http_variable_t *ngx_http_geoip2_new_variable(ngx_conf_t *cf,
    ngx_str_t *name);
static char *ngx_http_geoip2_proxy(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_geoip2_cidr_value(ngx_conf_t *cf, ngx_str_t *net,
    ngx_cidr_t *cidr);
static ngx_int_t ngx_http_geoip2_init(ngx_conf_t *cf);


static ngx_command_t  ngx_http_geoip2_commands[] = {

    { ngx_string("geoip2"),
        NGX_HTTP_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_TAKE1,
        ngx_http_geoip2,
        NGX_HTTP_MAIN_CONF_OFFSET,
        0,
        NULL },

    { ngx_string("geoip2_proxy"),
        NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
        ngx_http_geoip2_proxy,
        NGX_HTTP_MAIN_CONF_OFFSET,
        0,
        NULL },

    { ngx_string("geoip2_proxy_recursive"),
        NGX_HTTP_MAIN_CONF|NGX_CONF_FLAG,
        ngx_conf_set_flag_slot,
        NGX_HTTP_MAIN_CONF_OFFSET,
        offsetof(ngx_http_geoip2_conf_t, proxy_recursive),
        NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_geoip2_module_ctx = {
    NULL,                                  /* preconfiguration */
    ngx_http_geoip2_init,                  /* postconfiguration */

    ngx_http_geoip2_create_conf,           /* create main configuration */
    ngx_http_geoip2_init_conf,             /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};


ngx_module_t  ngx_http_geoip2_module = {
    NGX_MODULE_V1,
    &ngx_http_geoip2_module_ctx,           /* module context */
    ngx_http_geoip2_commands,              /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
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
ngx_http_geoip2_variable(ngx_http_request_t *r, ngx_http_variable_value_t *v,
    uintptr_t data)
{
    ngx_http_geoip2_ctx_t   *geoip2 = (ngx_http_geoip2_ctx_t *) data;
    ngx_int_t               rc;
    ngx_http_geoip2_conf_t  *gcf;
    ngx_addr_t              addr;
#if defined(nginx_version) && nginx_version >= 1023000
    ngx_table_elt_t         *xfwd;
#else
    ngx_array_t             *xfwd;
#endif
    ngx_str_t               val;

    if (geoip2->source.value.len > 0) {
        if (ngx_http_complex_value(r, &geoip2->source, &val) != NGX_OK) {  /* GCOVR_EXCL_BR_LINE */
            goto not_found;  /* GCOVR_EXCL_LINE */
        }

        if (ngx_parse_addr(r->pool, &addr, val.data, val.len) != NGX_OK) {
            goto not_found;
        }
    } else {
        gcf = ngx_http_get_module_main_conf(r, ngx_http_geoip2_module);
        addr.sockaddr = r->connection->sockaddr;
        addr.socklen = r->connection->socklen;

#if defined(nginx_version) && nginx_version >= 1023000
        xfwd = r->headers_in.x_forwarded_for;

        if (xfwd != NULL && gcf->proxies != NULL) {
#else
        xfwd = &r->headers_in.x_forwarded_for;

        if (xfwd->nelts > 0 && gcf->proxies != NULL) {
#endif
            (void) ngx_http_get_forwarded_addr(r, &addr, xfwd, NULL,
                                               gcf->proxies, gcf->proxy_recursive);
        }
    }

    rc = ngx_geoip2_lookup(r->pool, geoip2->database, addr.sockaddr,
                           geoip2->lookup, geoip2->escape, &val);

    return ngx_geoip2_value(v, rc, &val, &geoip2->default_value);

not_found:
    return ngx_geoip2_value(v, NGX_DECLINED, NULL, &geoip2->default_value);
}


static ngx_int_t
ngx_http_geoip2_metadata(ngx_http_request_t *r, ngx_http_variable_value_t *v,
    uintptr_t data)
{
    ngx_int_t  rc;
    ngx_str_t  val;

    rc = ngx_geoip2_metadata_value(r->pool, (ngx_geoip2_metadata_t *) data,
                                   &val);

    /* metadata has no default: its value is never declined */
    return ngx_geoip2_value(v, rc, &val, NULL);
}


static void *
ngx_http_geoip2_create_conf(ngx_conf_t *cf)
{
    ngx_pool_cleanup_t      *cln;
    ngx_http_geoip2_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_geoip2_conf_t));
    if (conf == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NULL;  /* GCOVR_EXCL_LINE */
    }

    conf->proxy_recursive = NGX_CONF_UNSET;

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
ngx_http_geoip2(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_geoip2_conf_t  *gcf = conf;
    char                    *rv;
    ngx_conf_t              save;
    ngx_geoip2_db_t         *database;

    rv = ngx_geoip2_open(cf, &gcf->databases, &database);
    if (rv != NGX_CONF_OK) {
        return rv;
    }

    save = *cf;
    cf->handler = ngx_http_geoip2_parse_config;
    cf->handler_conf = (void *) database;

    rv = ngx_conf_parse(cf, NULL);
    *cf = save;
    return rv;
}


static char *
ngx_http_geoip2_parse_config(ngx_conf_t *cf, ngx_command_t *dummy, void *conf)
{
    ngx_str_t  *value;

    value = cf->args->elts;

    if (value[0].data[0] == '$') {
        return ngx_http_geoip2_add_variable(cf, conf);
    }

    return ngx_geoip2_setting(cf, conf);
}


static char *
ngx_http_geoip2_add_variable(ngx_conf_t *cf, ngx_geoip2_db_t *database)
{
    char                              *rv;
    ngx_str_t                         *value, source;
    ngx_http_variable_t               *var;
    ngx_http_geoip2_ctx_t             *geoip2;
    ngx_geoip2_metadata_t             *metadata;
    ngx_http_compile_complex_value_t  ccv;

    value = cf->args->elts;

    /* ngx_http_geoip2_parse_config calls this only for a name with a '$' */
    value[0].len--;
    value[0].data++;

    if (ngx_geoip2_is_metadata(cf)) {
        rv = ngx_geoip2_metadata(cf, database, &metadata);
        if (rv != NGX_CONF_OK) {
            return rv;
        }

        var = ngx_http_geoip2_new_variable(cf, &value[0]);
        if (var == NULL) {
            return NGX_CONF_ERROR;
        }

        var->get_handler = ngx_http_geoip2_metadata;
        var->data = (uintptr_t) metadata;

        return NGX_CONF_OK;
    }

    geoip2 = ngx_pcalloc(cf->pool, sizeof(ngx_http_geoip2_ctx_t));
    if (geoip2 == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    geoip2->database = database;

    rv = ngx_geoip2_variable(cf, &geoip2->default_value, &source,
                             &geoip2->escape, &geoip2->lookup);
    if (rv != NGX_CONF_OK) {
        return rv;
    }

    if (source.len > 0) {
        ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));
        ccv.cf = cf;
        ccv.value = &source;
        ccv.complex_value = &geoip2->source;

        if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "unable to compile \"%V\" for \"$%V\"",
                               &source, &value[0]);
            return NGX_CONF_ERROR;
        }
    }

    var = ngx_http_geoip2_new_variable(cf, &value[0]);
    if (var == NULL) {
        return NGX_CONF_ERROR;
    }

    var->get_handler = ngx_http_geoip2_variable;
    var->data = (uintptr_t) geoip2;

    return NGX_CONF_OK;
}


/*
 * Adds the variable of a geoip2 block. Rejects a name that a geoip2 block
 * already defines: nginx would return that variable, and the new handler
 * would replace the old one without a word.
 */
static ngx_http_variable_t *
ngx_http_geoip2_new_variable(ngx_conf_t *cf, ngx_str_t *name)
{
    ngx_http_variable_t  *var;

    var = ngx_http_add_variable(cf, name, NGX_HTTP_VAR_CHANGEABLE);
    if (var == NULL) {
        return NULL;
    }

    if (var->get_handler == ngx_http_geoip2_variable
        || var->get_handler == ngx_http_geoip2_metadata)
    {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "the duplicate geoip2 variable \"$%V\"", name);
        return NULL;
    }

    return var;
}


static char *
ngx_http_geoip2_init_conf(ngx_conf_t *cf, void *conf)
{
    ngx_http_geoip2_conf_t  *gcf = conf;
    ngx_conf_init_value(gcf->proxy_recursive, 0);
    return NGX_CONF_OK;
}


static char *
ngx_http_geoip2_proxy(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_geoip2_conf_t  *gcf = conf;
    ngx_str_t               *value;
    ngx_cidr_t              cidr, *c;

    value = cf->args->elts;

    if (ngx_http_geoip2_cidr_value(cf, &value[1], &cidr) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (gcf->proxies == NULL) {
        gcf->proxies = ngx_array_create(cf->pool, 4, sizeof(ngx_cidr_t));
        if (gcf->proxies == NULL) {  /* GCOVR_EXCL_BR_LINE */
            return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
        }
    }

    c = ngx_array_push(gcf->proxies);
    if (c == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_CONF_ERROR;  /* GCOVR_EXCL_LINE */
    }

    *c = cidr;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_geoip2_cidr_value(ngx_conf_t *cf, ngx_str_t *net, ngx_cidr_t *cidr)
{
    ngx_int_t  rc;

    if (ngx_strcmp(net->data, "255.255.255.255") == 0) {
        cidr->family = AF_INET;
        cidr->u.in.addr = 0xffffffff;
        cidr->u.in.mask = 0xffffffff;

        return NGX_OK;
    }

    rc = ngx_ptocidr(net, cidr);

    if (rc == NGX_ERROR) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid network \"%V\"", net);
        return NGX_ERROR;
    }

    if (rc == NGX_DONE) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "low address bits of %V are meaningless", net);
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_geoip2_log_handler(ngx_http_request_t *r)
{
    ngx_http_geoip2_conf_t  *gcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "geoip2 http log handler");

    gcf = ngx_http_get_module_main_conf(r, ngx_http_geoip2_module);

    ngx_geoip2_reload(&gcf->databases, r->connection->log);

    return NGX_OK;
}


static ngx_int_t
ngx_http_geoip2_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_LOG_PHASE].handlers);
    if (h == NULL) {  /* GCOVR_EXCL_BR_LINE */
        return NGX_ERROR;  /* GCOVR_EXCL_LINE */
    }

    *h = ngx_http_geoip2_log_handler;

    return NGX_OK;
}
