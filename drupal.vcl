# https://www.varnish-cache.org/lists/pipermail/varnish-misc/2011-March/020182.html
/* A backend that will always fail. */
backend failapp {
    .host = "127.0.0.1";
    .port = "9000";
    .probe = {
        .url = "/hello/";
        .interval = 12h;
        .timeout = 1s;
        .window = 1;
        .threshold = 1;
    }
}
 
# Respond to incoming requests.
sub vcl_recv {
    # https://www.varnish-cache.org/lists/pipermail/varnish-misc/2011-March/020182.html
    if (req.http.X-Varnish-Error == "1") {
        set req.backend = failapp;
            unset req.http.X-Varnish-Error;
            set req.http.X-Varnish-LookupFailure= "1";
    } else {
        set req.backend = default_director;
    }
    if (! req.backend.healthy) {
        set req.grace = 24h;
    } else {
        set req.grace = 1m;
    }
 
  # Pipe these paths directly to Apache for streaming.
  if (req.url ~ "^/admin/content/backup_migrate/export" || 
      req.url ~ "^/sites/default/files/import.xml" ||
      req.url ~ "^/colorbox/.*$") {
    return (pipe);
  }
 
  # Do not cache these paths.
  if (req.url ~ "^/status\.php$" ||
      req.url ~ "^/update\.php$" ||
      req.url ~ "^/admin$" ||
      req.url ~ "^/admin/.*$" ||
      req.url ~ "^/user$" ||
      req.url ~ "^/user/.*$" ||
      req.url ~ "^/flag/.*$" ||
      req.url ~ "^.*/ajax/.*$" ||
      req.url ~ "^/colorbox/.*$" ||
      req.url ~ "^sites/default/files/import.xml" ||
      req.url ~ "^.*/ahah/.*$") {
       return (pass);
  }
 
  # Do not allow outside access to cron.php or install.php.
  #if (req.url ~ "^/(cron|install)\.php$" && !client.ip ~ internal) {
    # Have Varnish throw the error directly.
  #  error 404 "Page not found.";
    # Use a custom error page that you've defined in Drupal at the path "404".
    # set req.url = "/404";
  #}
 
  # Always cache the following file types for all users. This list of extensions
  # appears twice, once here and again in vcl_fetch so make sure you edit both
  # and keep them equal.
  if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
    unset req.http.Cookie;
  }
 
  # Remove all cookies that Drupal doesn't need to know about. We explicitly 
  # list the ones that Drupal does need, the SESS and NO_CACHE. If, after 
  # running this code we find that either of these two cookies remains, we 
  # will pass as the page cannot be cached.
  if (req.http.Cookie) {
    # 1. Append a semi-colon to the front of the cookie string.
    # 2. Remove all spaces that appear after semi-colons.
    # 3. Match the cookies we want to keep, adding the space we removed 
    #    previously back. (\1) is first matching group in the regsuball.
    # 4. Remove all other cookies, identifying them by the fact that they have
    #    no space after the preceding semi-colon.
    # 5. Remove all spaces and semi-colons from the beginning and end of the 
    #    cookie string. 
    set req.http.Cookie = ";" + req.http.Cookie;
    set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");    
    set req.http.Cookie = regsuball(req.http.Cookie, ";(SESS[a-z0-9]+|NO_CACHE|location)=", "; \1=");
    set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");
 
    if (req.http.Cookie == "") {
      # If there are no remaining cookies, remove the cookie header. If there
      # aren't any cookie headers, Varnish's default behavior will be to cache
      # the page.
      unset req.http.Cookie;
    }
    else if (req.http.Cookie ~ "SESS[a-z0-9]+|NO_CACHE") {
      # If there is any cookies left (a session or NO_CACHE cookie), do not
      # cache the page. Pass it on to Apache directly.
      return (pass);
    }
    if (req.restarts == 0) {
        if (req.http.x-forwarded-for) {
          set req.http.X-Forwarded-For =
          req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }
    if (req.request != "GET" &&
      req.request != "HEAD" &&
      req.request != "PUT" &&
      req.request != "POST" &&
      req.request != "TRACE" &&
      req.request != "OPTIONS" &&
      req.request != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }
    if (req.request != "GET" && req.request != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }
    if (req.http.Authorization) {
        /* Not cacheable by default */
        return (pass);
    }
    return (lookup);
  }
}

sub vcl_deliver {
  # Set a header to track a cache HIT/MISS.
  if (obj.hits > 0) {
    set resp.http.X-Varnish-Cache = "HIT";
  }
  else {
    set resp.http.X-Varnish-Cache = "MISS";
  }
}
 
# Code determining what to do when serving items from the Apache servers.
# beresp == Back-end response from the web server.
sub vcl_fetch {
  # We need this to cache 404s, 301s, 500s. Otherwise, depending on backend but 
  # definitely in Drupal's case these responses are not cacheable by default.
  if (beresp.status == 404 || beresp.status == 301 || beresp.status == 500) {
    set beresp.ttl = 10m;
  }
 
  # Don't allow static files to set cookies. 
  # (?i) denotes case insensitive in PCRE (perl compatible regular expressions).
  # This list of extensions appears twice, once here and again in vcl_recv so 
  # make sure you edit both and keep them equal.
  if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
    unset beresp.http.set-cookie;
  }
 
  # Allow items to be stale if needed.
  set beresp.grace = 24h;
  
  # https://www.varnish-cache.org/trac/wiki/VCLExampleLongerCaching
  # If front page, then remove un-needed expire and age headers.
  if (req.url ~ "^/$") {
    /* Remove Expires from backend, it's not long enough */
    unset beresp.http.expires;

    /* Set how long Varnish will keep it */
    set beresp.ttl = 1w;
  }
}
 
sub vcl_error {
    # https://www.varnish-cache.org/lists/pipermail/varnish-misc/2011-March/020182.html
    if ( req.http.X-Varnish-Error != "1" && req.http.X-Varnish-LookupFailure != "1" ) {
        set req.http.X-Varnish-Error = "1";
        return (restart);
    }

  # In the event of an error, show friendlier messages.
  # And redirect to the homepage, which will likely be in the cache.
  set obj.http.Content-Type = "text/html; charset=utf-8";
  synthetic {"
<html>
<head>
  <title>Page Unavailable</title>
  <style>
    body { background: #303030; text-align: center; color: white; }
    #page { border: 1px solid #CCC; width: 500px; margin: 100px auto 0; padding: 30px; background: #323232; }
    a, a:link, a:visited { color: #CCC; }
    .error { color: #222; }
  </style>
</head>
<body onload="setTimeout(function() { window.location = '/' }, 5000)">
  <div id="page">
    <h1 class="title">Page Unavailable</h1>
    <p>The page you requested is temporarily unavailable.</p>
    <p>We're redirecting you to the <a href="/">homepage</a> in 5 seconds.</p>
    <div class="error">(Error "} + obj.status + " " + obj.response + {")</div>
  </div>
</body>
</html>
"};
  return (deliver);
}

sub vcl_pipe {
    # http://www.varnish-cache.org/ticket/451
    # This forces every pipe request to be the first one.
    set bereq.http.connection = "close";
}

### vcl_hash creates the key for varnish under which the object is stored. It is
### possible to store the same url under 2 different keys, by making vcl_hash
### create a different hash.
sub vcl_hash {
    ### these 2 entries are the default ones used for vcl. Below we add our own.
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    ### regsub replaces only the bit in your match criteria with whatever you
    ### ask it too. In this case, we need to remove *EVERYTHING* else from the
    ### cookie, except the location text, hence the full string match
    if( req.http.Cookie ~ "location" ) {
        set req.http.X-Varnish-Hashed-On =
            regsub( req.http.Cookie, "^.*?location=([^;]*);*.*$", "\1" );
    }

    ### if the request is location specific, add the location to the hashing
    if( req.http.X-Varnish-Hashed-On ) {
        hash_data(req.http.X-Varnish-Hashed-On);
    }

    return (hash);
}
 
#
# Below is a commented-out copy of the default VCL logic.  If you
# redefine any of these subroutines, the built-in logic will be
# appended to your code.
# sub vcl_recv {
#     if (req.restarts == 0) {
#   if (req.http.x-forwarded-for) {
#       set req.http.X-Forwarded-For =
#       req.http.X-Forwarded-For + ", " + client.ip;
#   } else {
#       set req.http.X-Forwarded-For = client.ip;
#   }
#     }
#     if (req.request != "GET" &&
#       req.request != "HEAD" &&
#       req.request != "PUT" &&
#       req.request != "POST" &&
#       req.request != "TRACE" &&
#       req.request != "OPTIONS" &&
#       req.request != "DELETE") {
#         /* Non-RFC2616 or CONNECT which is weird. */
#         return (pipe);
#     }
#     if (req.request != "GET" && req.request != "HEAD") {
#         /* We only deal with GET and HEAD by default */
#         return (pass);
#     }
#     if (req.http.Authorization || req.http.Cookie) {
#         /* Not cacheable by default */
#         return (pass);
#     }
#     return (lookup);
# }
#
# sub vcl_pipe {
#     # Note that only the first request to the backend will have
#     # X-Forwarded-For set.  If you use X-Forwarded-For and want to
#     # have it set for all requests, make sure to have:
#     # set bereq.http.connection = "close";
#     # here.  It is not set by default as it might break some broken web
#     # applications, like IIS with NTLM authentication.
#     return (pipe);
# }
#
# sub vcl_pass {
#     return (pass);
# }
#
# sub vcl_hash {
#     hash_data(req.url);
#     if (req.http.host) {
#         hash_data(req.http.host);
#     } else {
#         hash_data(server.ip);
#     }
#     return (hash);
# }
#
# sub vcl_hit {
#     return (deliver);
# }
#
# sub vcl_miss {
#     return (fetch);
# }
#
# sub vcl_fetch {
#     if (beresp.ttl <= 0s ||
#         beresp.http.Set-Cookie ||
#         beresp.http.Vary == "*") {
#       /*
#        * Mark as "Hit-For-Pass" for the next 2 minutes
#        */
#       set beresp.ttl = 120 s;
#       return (hit_for_pass);
#     }
#     return (deliver);
# }
#
# sub vcl_deliver {
#     return (deliver);
# }
#
# sub vcl_error {
#     set obj.http.Content-Type = "text/html; charset=utf-8";
#     set obj.http.Retry-After = "5";
#     synthetic {"
# <?xml version="1.0" encoding="utf-8"?>
# <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
#  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
# <html>
#   <head>
#     <title>"} + obj.status + " " + obj.response + {"</title>
#   </head>
#   <body>
#     <h1>Error "} + obj.status + " " + obj.response + {"</h1>
#     <p>"} + obj.response + {"</p>
#     <h3>Guru Meditation:</h3>
#     <p>XID: "} + req.xid + {"</p>
#     <hr>
#     <p>Varnish cache server</p>
#   </body>
# </html>
# "};
#     return (deliver);
# }
#
# sub vcl_init {
#   return (ok);
# }
#
# sub vcl_fini {
#   return (ok);
# }

