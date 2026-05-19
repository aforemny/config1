{
  overlays.ipv6-lib = self: super: {
    lib = super.lib.extend (
      self: super:
      let
        ipv6 = {
          mkIPv6 =
            prefix: hostName: interface:
            let
              h = builtins.hashString "sha256" (
                builtins.concatStringsSep "/" [
                  hostName
                  interface
                ]
              );
              group = n: builtins.substring (n * 4) 4 h;
            in
            {
              address = "${prefix}:${group 0}:${group 1}:${group 2}:${group 3}";
              prefixLength = 64;
            };
        };
      in
      {
        inherit ipv6;
        inherit (ipv6) mkIPv6;
      }
    );
  };
}
