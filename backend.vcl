# https://www.varnish-cache.org/trac/wiki/LoadBalancing
backend default {
  .host = "localhost";
  .port = "8080";
  .first_byte_timeout = 300s;
  .connect_timeout = 300s;
  .between_bytes_timeout = 300s;
  .probe = { .url = "/status.php"; .interval = 15s; .timeout = 5s; .window = 8;.threshold = 3; }
}

# Define the director that determines how to distribute incoming requests.
director default_director round-robin {
  { .backend = default; }
}

sub vcl_recv {
  set req.backend = default_director;
}

