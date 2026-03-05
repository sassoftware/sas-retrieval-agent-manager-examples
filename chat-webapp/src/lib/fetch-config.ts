process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

/**
 * Configure fetch options to handle self-signed SSL certificates
 *
 * WARNING: This example application disables SSL certificate verification.
 * DO NOT USE THIS IN PRODUCTION. Always use proper SSL certificates signed
 * by a trusted Certificate Authority in production environments.
 */
export function getFetchConfig(): RequestInit {
  return {};
}
