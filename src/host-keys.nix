{ lib, ... }:
let
  hostPubkeys = {
    apu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGL/D6K8Ks28fv78FUUTS/6h8H26bJcHdfdfqAwgQqjU";
    m1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1sp46+MP5LXrV/OZyD+RDt4LT7xwDDkC3lvx8pzgKL";
    tower = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE3kGQEQx8+drQ1D9VrmZXVfcit0fGV+4oTlHk54DtTl";
    x1e = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGwtRxzp/roHcVltBW3n5dWqoP6NlRYNGuJTOEwBWBmK";
  };
in
{
  systems = lib.mapAttrs (system: hostPubkey: {
    modules = [ { age.rekey = { inherit hostPubkey; }; } ];
  }) hostPubkeys;
}
