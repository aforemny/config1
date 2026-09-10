{
  # One ACME account for every host that terminates TLS. Declared globally so a
  # service module only has to mark its vhost `enableACME`, instead of each one
  # repeating the account terms and contact address.
  nixosModules.acme = {
    security.acme = {
      acceptTerms = true;
      defaults.email = "aforemny@posteo.de";
    };
  };
}
