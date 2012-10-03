<?php
// Cache settings
$conf['page_cache_invoke_hooks'] = false;
$conf['reverse_proxy'] = true;
$conf['cache'] = 1;
$conf['cache_lifetime'] = 0;
$conf['page_cache_maximum_age'] = 21600;
$conf['reverse_proxy_header'] = 'HTTP_X_FORWARDED_FOR';
$conf['reverse_proxy_addresses'] = array('10.0.0.1,10.0.0.2');  # Web Server IP addresses
$conf['omit_vary_cookie'] = true;

// Varnish settings
$conf['cache_backends'] = array('sites/all/modules/varnish/varnish.cache.inc');
$conf['cache_class_cache_page'] = 'VarnishCache';
$conf['varnish_version'] = '3';
$conf['varnish_cache_clear'] = 2;
$conf['varnish_control_terminal'] = 'varnishHost1:6082 varnishHost2:6082';
$conf['varnish_control_key'] = '111aaaa1-aaa1-1a11-a111-111a11a11111'; # Must sync the control keys for all varnish servers

// Purge settings
$conf['purge_proxy_urls'] = 'http://varnishHost1:80 http://varnishHost2:80'; # Varnish servers

