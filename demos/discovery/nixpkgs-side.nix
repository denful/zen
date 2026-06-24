# demos/discovery/nixpkgs-side.nix
# In nixpkgs the consumer MUST hardcode the provider's option path
# (config.services.redis.url). There is no capability namespace, no broker, no
# discover-by-name: swapping redis->memcached means EDITING the consumer.
let
  lib = import <nixpkgs/lib>;
  # A minimal evalModules that shows the hardcoded-path structure.
  # The consumer option references config.services.redis.url by path — not by
  # capability name. To swap the provider the consumer must be edited.
  m = lib.evalModules {
    modules = [
      {
        options.services.redis.url = lib.mkOption {
          type = lib.types.str;
          default = "redis://10.0.0.1";
        };
      }
      {
        options.client.cacheUrl = lib.mkOption {
          type = lib.types.str;
          # Consumer hardcodes the provider PATH — no capability indirection.
          default = "hardcoded-to-services.redis.url";
        };
        config.client.cacheUrl = lib.mkDefault m.config.services.redis.url;
      }
    ];
  };
in
{
  # The consumer references a specific provider path; swapping providers requires editing this.
  consumerMustReference = "config.services.redis.url";
  swapProviderRequiresConsumerEdit = true;
  hasCapabilityNamespace = false;
  # The settled value: consumer receives the hardcoded redis URL.
  settledCacheUrl = m.config.client.cacheUrl;
}
