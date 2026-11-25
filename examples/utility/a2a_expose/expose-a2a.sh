#!/usr/bin/env bash
# Select a running RAM agent. Configure its public A2A route.
set -euo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Select a running RAM agent with a valid configured agent card.
Expose the agent through NGINX Ingress or Contour HTTPProxy.
Detect missing settings from existing RAM routes. Select an agent from the list.
Supply --agent-id to skip agent selection. Prompt for unresolved settings.

Options:
  --context NAME                 Kubernetes context
  --namespace NAME               Agent namespace (retagentmgr)
  --ram-url URL                  RAM base URL (detect or prompt when omitted)
  --agent-id ID                  Select one available agent
  --mode ingress|httpproxy       Exposure mode (detect or prompt when omitted)
  --public-base-url URL          Public URL (detect or prompt when omitted)
  --base-path PATH               Fallback path (/SASRetrievalAgentManager)
  --http-proxy-name NAME         Parent HTTPProxy (retrieval-agent-manager-ingress)
  --extension-namespace NAME     Parent namespace (agent namespace)
  --ingress-class-name NAME      Ingress class (nginx, or the parent Contour class)
  --tls-secret-name NAME         NGINX TLS Secret in the agent namespace
  --timeout-seconds NUMBER       Request and HTTPProxy timeout (60)
  --keycloak-url URL             Keycloak base URL (RAM URL plus /auth)
  --keycloak-realm NAME          Keycloak realm (sas-iot)
  --keycloak-client-id ID        Public device client (sas-ram-api)
  --ca-cert FILE                 Optional trusted PEM bundle override
  --list-only                    List available agents without route changes
  --dry-run                      Show operations without route changes
  --help                        Show this help

Sign in with the displayed device code before RAM data requests.
Set RAM_AUTHORIZATION to use an existing HTTP Authorization value instead.
If HTTPS trust fails, read the matching TLS certificate from Kubernetes.
EOF
}

context= namespace=retagentmgr ram_url= agent_id= mode= public_base_url=
base_path=/SASRetrievalAgentManager http_proxy_name=retrieval-agent-manager-ingress
extension_namespace= ingress_class_name= tls_secret_name= timeout_seconds=60
list_only=false dry_run=false
keycloak_url= keycloak_realm=sas-iot keycloak_client_id=sas-ram-api ca_cert=
public_base_url_explicit=false base_path_explicit=false tls_secret_explicit=false
while (($#)); do
  case "$1" in
    --list-only) list_only=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --help | -h) usage; exit 0 ;;
    --context | --namespace | --ram-url | --agent-id | --mode | --public-base-url | --base-path | \
      --http-proxy-name | --extension-namespace | --ingress-class-name | --tls-secret-name | --timeout-seconds | \
      --keycloak-url | --keycloak-realm | --keycloak-client-id | --ca-cert)
      [[ $# -ge 2 && "$2" != --* ]] || die "$1 requires a value."
      case "$1" in
        --context) context=$2 ;; --namespace) namespace=$2 ;; --ram-url) ram_url=$2 ;;
        --agent-id) agent_id=$2 ;; --mode) mode=$2 ;;
        --public-base-url) public_base_url=$2; public_base_url_explicit=true ;;
        --base-path) base_path=$2; base_path_explicit=true ;; --http-proxy-name) http_proxy_name=$2 ;;
        --extension-namespace) extension_namespace=$2 ;; --ingress-class-name) ingress_class_name=$2 ;;
        --tls-secret-name) tls_secret_name=$2; tls_secret_explicit=true ;; --timeout-seconds) timeout_seconds=$2 ;;
        --keycloak-url) keycloak_url=$2 ;; --keycloak-realm) keycloak_realm=$2 ;;
        --keycloak-client-id) keycloak_client_id=$2 ;; --ca-cert) ca_cert=$2 ;;
      esac
      shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done
[[ "$timeout_seconds" =~ ^[1-9][0-9]{0,2}$ ]] && ((timeout_seconds <= 600)) ||
  die 'The timeout must be between 1 and 600 seconds.'
[[ -z "$mode" || "$mode" == ingress || "$mode" == httpproxy ]] || die 'Use ingress or httpproxy.'
for executable in kubectl curl jq sha256sum openssl; do
  command -v "$executable" >/dev/null || die "$executable is required."
done
curl_arguments=(--silent --show-error)
if [[ -n "$ca_cert" ]]; then
  [[ -f "$ca_cert" && -r "$ca_cert" ]] || die 'The CA certificate bundle must be a readable file.'
  curl_arguments+=(--cacert "$ca_cert")
fi
kube_arguments=("--request-timeout=${timeout_seconds}s")
if [[ -n "$context" ]]; then kube_arguments+=(--context "$context"); fi
kube() { kubectl "${kube_arguments[@]}" "$@"; }
get_object() {
  local text
  text=$(kube -n "$3" get "$1" "$2" --ignore-not-found -o json) || return 1
  printf '%s\n' "${text:-null}"
}
select_number() {
  local label=$1 limit=$2 answer
  while :; do
    read -r -p "$label: " answer || die 'A selection is required. Supply the corresponding option when input is not available.'
    if [[ "$answer" =~ ^[1-9][0-9]{0,5}$ ]] && ((answer <= limit)); then
      selection=$((answer - 1))
      return
    fi
    printf 'The selection is not valid. Select a number from the list.\n' >&2
  done
}
prompt_required() {
  local destination=$1 label=$2 answer
  while :; do
    read -r -p "$label: " answer || die "$label is required. Supply the corresponding option when input is not available."
    if [[ -n "$answer" ]]; then printf -v "$destination" '%s' "$answer"; return; fi
    printf 'A value is required.\n' >&2
  done
}
printf 'Context: %s; agent namespace: %s\n' "${context:-current}" "$namespace" >&2
extension_namespace=${extension_namespace:-$namespace}
if [[ -z "$ram_url" ]] || { ! $list_only && [[ -z "$mode" || -z "$public_base_url" ||
    ( "$mode" == ingress && "$public_base_url" == https://* && -z "$tls_secret_name" ) ]]; }; then
  candidates='[]'
  if [[ "$mode" != httpproxy ]]; then
    ingresses=$(kube -n "$namespace" get ingresses -o json)
    candidates=$(jq --arg prefix "${base_path%/}/postgrest" --arg path "${base_path%/}" '
      [.items[] as $ingress |
        ($ingress.spec.ingressClassName // $ingress.metadata.annotations["kubernetes.io/ingress.class"] // "") as $class |
        select($class == "nginx" or any(($ingress.metadata.annotations // {}) | keys[];
          startswith("nginx.ingress.kubernetes.io/"))) |
        $ingress.spec.rules[] | .host as $host | .http.paths[] |
        select(.path == $prefix or (.path | startswith($prefix + "/") or startswith($prefix + "("))) |
        [$ingress.spec.tls[]? | select(any(.hosts[]?; . == $host))] as $tls |
        (if ($tls | length) > 0 then $tls[] | .secretName // "" else "" end) as $secret |
        {mode:"ingress",url:((if ($tls | length) > 0 or
          $ingress.metadata.annotations["nginx.ingress.kubernetes.io/force-ssl-redirect"] == "true"
          then "https" else "http" end) + "://" + $host + $path),
         class:(if $class == "" then "nginx" else $class end),secret:$secret,
         source:$ingress.metadata.name}
      ] | unique_by([.mode,.url,.class,.secret])' <<<"$ingresses")
  fi
  if [[ "$mode" != ingress ]]; then
    contour_resources=$(kube api-resources --api-group=projectcontour.io -o name)
    if grep -Fxq httpproxies.projectcontour.io <<<"$contour_resources"; then
      detected_parent=$(get_object httpproxy "$http_proxy_name" "$extension_namespace")
      contour_candidate=$(jq --arg path "${base_path%/}" '
        if .spec.virtualhost.fqdn then [{mode:"httpproxy",
          url:((if .spec.virtualhost.tls then "https" else "http" end) + "://" + .spec.virtualhost.fqdn + $path),
          class:(.spec.ingressClassName // ""),secret:"",source:.metadata.name}] else [] end' <<<"$detected_parent")
      candidates=$(printf '%s\n%s\n' "$candidates" "$contour_candidate" | jq -s '.[0] + .[1]')
    fi
  fi
  candidate_count=$(jq 'length' <<<"$candidates")
  if ((candidate_count > 0)); then
    selection=0
    if ((candidate_count > 1)); then
      printf 'Multiple RAM routes are available.\n' >&2
      jq -r 'to_entries[] | "\(.key + 1). \(.value.mode) | \(.value.url) | \(.value.source)"' <<<"$candidates" >&2
      select_number 'Select a RAM route number' "$candidate_count"
    fi
    detected=$(jq -c --argjson index "$selection" '.[$index]' <<<"$candidates")
    detected_url=$(jq -r '.url' <<<"$detected")
    ram_url=${ram_url:-$detected_url}
    mode=${mode:-$(jq -r '.mode' <<<"$detected")}
    public_base_url=${public_base_url:-$detected_url}
    if [[ "${public_base_url%/}" == "${detected_url%/}" ]]; then
      ingress_class_name=${ingress_class_name:-$(jq -r '.class' <<<"$detected")}
      tls_secret_name=${tls_secret_name:-$(jq -r '.secret' <<<"$detected")}
    fi
    printf 'Detected RAM routing: %s | %s\n' "$mode" "$detected_url" >&2
  else
    printf 'No matching RAM route was found. Supply the unresolved settings.\n' >&2
  fi
fi
if [[ -z "$ram_url" ]]; then prompt_required ram_url 'RAM base URL (include the application path)'; fi
[[ "$ram_url" =~ ^https?://[^/?#@]+(/[^?#]*)?$ ]] || die 'The RAM base URL is not valid.'
postgrest_url="${ram_url%/}/postgrest"

umask 077
temporary_directory=$(mktemp -d)
headers_file="$temporary_directory/headers"
patch_file="$temporary_directory/patch.json"
page_file="$temporary_directory/page.json"
definitions_file="$temporary_directory/definitions.json"
champions_file="$temporary_directory/champions.json"
services_file="$temporary_directory/services.json"
pods_file="$temporary_directory/pods.json"
verifier_file="$temporary_directory/verifier"
form_file="$temporary_directory/form"
device_file="$temporary_directory/device.json"
token_file="$temporary_directory/token.json"
cluster_ca_file="$temporary_directory/cluster-ca.pem"
certificate_file="$temporary_directory/certificates.pem"
normalized_certificate_file="$temporary_directory/normalized-certificates.pem"
http_error_file="$temporary_directory/http-error"
trap 'rm -f -- "$headers_file" "$patch_file" "$page_file" "$definitions_file" "$champions_file" "$services_file" "$pods_file" "$verifier_file" "$form_file" "$device_file" "$token_file" "$cluster_ca_file" "$certificate_file" "$normalized_certificate_file" "$http_error_file"; rmdir -- "$temporary_directory"' EXIT

trust_cluster_certificates() {
  local url=$1 authority host resource_namespace resources references='[]' found contour_resources
  local reference secret_namespace secret_name encoded certificate cluster_settings certificate_count=0
  authority=${url#https://}
  authority=${authority%%/*}
  host=${authority%%:*}
  host=${host,,}
  cluster_settings=$(kube config view --minify \
    -o 'jsonpath={.clusters[0].cluster.server}{"|"}{.clusters[0].cluster.insecure-skip-tls-verify}')
  [[ "${cluster_settings%%|*}" == https://* && "${cluster_settings#*|}" != true ]] ||
    die 'Automatic certificate trust requires a verified HTTPS connection to the Kubernetes API server.'
  printf 'Read HTTPS certificates from Kubernetes for %s.\n' "$host" >&2
  for resource_namespace in "$namespace" "$extension_namespace"; do
    resources=$(kube -n "$resource_namespace" get ingresses -o json)
    found=$(jq --arg namespace "$resource_namespace" '
      [.items[] as $ingress | $ingress.spec.tls[]? |
       {namespace:($ingress.metadata.namespace // $namespace), name:.secretName, hosts:(.hosts // [])}]
    ' <<<"$resources")
    references=$(printf '%s\n%s\n' "$references" "$found" | jq -s '.[0] + .[1]')
    if [[ "$namespace" == "$extension_namespace" ]]; then break; fi
  done
  contour_resources=$(kube api-resources --api-group=projectcontour.io -o name)
  if grep -Fxq httpproxies.projectcontour.io <<<"$contour_resources"; then
    for resource_namespace in "$namespace" "$extension_namespace"; do
      resources=$(kube -n "$resource_namespace" get httpproxies -o json)
      found=$(jq --arg namespace "$resource_namespace" '
        [.items[] | select(.spec.virtualhost.tls.secretName != null) |
         {namespace:(.metadata.namespace // $namespace),name:.spec.virtualhost.tls.secretName,
          hosts:[.spec.virtualhost.fqdn]}]
      ' <<<"$resources")
      references=$(printf '%s\n%s\n' "$references" "$found" | jq -s '.[0] + .[1]')
      if [[ "$namespace" == "$extension_namespace" ]]; then break; fi
    done
  fi
  references=$(jq --arg host "$host" '
    def matches_host:
      if type != "string" then false else ascii_downcase as $pattern |
        $pattern == $host or (($pattern | startswith("*.")) and
          ($host | endswith($pattern[1:])) and
          (($host | split(".") | length) == ($pattern | split(".") | length)))
      end;
    [.[] | select((.name | type == "string" and length > 0) and any(.hosts[]; matches_host)) |
      (.name | split("/")) as $parts |
      if ($parts | length) == 2 then .namespace=$parts[0] | .name=$parts[1] else . end]
    | unique_by([.namespace,.name])
  ' <<<"$references")
  [[ $(jq 'length' <<<"$references") -gt 0 ]] ||
    die "No TLS Secret matches $host in the selected namespaces. Check the Ingress or HTTPProxy certificate settings."
  : >"$certificate_file"
  while IFS= read -r reference; do
    secret_namespace=$(jq -r '.namespace' <<<"$reference")
    secret_name=$(jq -r '.name' <<<"$reference")
    # Select only public certificates. Do not write the Secret's private key.
    encoded=$(kube -n "$secret_namespace" get secret "$secret_name" \
      -o 'jsonpath={.data.ca\.crt}{"\n"}{.data.tls\.crt}{"\n"}')
    while IFS= read -r certificate; do
      [[ -n "$certificate" ]] || continue
      printf '%s' "$certificate" | base64 --decode >>"$certificate_file"
      printf '\n' >>"$certificate_file"
      certificate_count=$((certificate_count + 1))
    done <<<"$encoded"
  done < <(jq -c '.[]' <<<"$references")
  ((certificate_count > 0)) || die "The TLS Secrets for $host contain no ca.crt or tls.crt certificates."
  openssl crl2pkcs7 -nocrl -certfile "$certificate_file" |
    openssl pkcs7 -print_certs -out "$normalized_certificate_file"
  grep -q -- '-----BEGIN CERTIFICATE-----' "$normalized_certificate_file" ||
    die "The TLS Secrets for $host do not contain valid PEM certificates."
  if [[ ! -f "$cluster_ca_file" ]]; then
    cat /etc/ssl/certs/ca-certificates.crt >"$cluster_ca_file"
    curl_arguments+=(--cacert "$cluster_ca_file")
  fi
  cat "$normalized_certificate_file" >>"$cluster_ca_file"
  printf 'Use the cluster TLS certificates for %s. HTTPS verification remains enabled.\n' "$host" >&2
}

http_request() {
  local method=$1 url=$2 output=$3 body=${4:-} limit=${5:-$timeout_seconds} status exit_code
  local arguments=("${curl_arguments[@]}" --max-time "$limit" --output "$output" --write-out '%{http_code}')
  if [[ "$method" == POST ]]; then
    arguments+=(--header 'Accept: application/json' --header 'Content-Type: application/x-www-form-urlencoded'
      --data-binary "@$body")
  else
    arguments+=(--header "@$headers_file")
  fi
  if status=$(curl "${arguments[@]}" "$url" 2>"$http_error_file"); then
    http_status=$status
  else
    exit_code=$?
    if ((exit_code == 60)) && [[ -z "$ca_cert" ]]; then
      trust_cluster_certificates "$url"
      if status=$(curl "${arguments[@]}" --cacert "$cluster_ca_file" "$url" 2>"$http_error_file"); then
        http_status=$status
        return
      else
        exit_code=$?
      fi
    fi
    cat "$http_error_file" >&2
    if ((exit_code == 60)); then
      die 'TLS certificate verification failed. Check the route certificate, hostname, certificate validity, and issuer chain.'
    fi
    die "The HTTP request failed (curl exit $exit_code)."
  fi
}
oauth_failure() {
  local stage=$1 response=$2 error_code
  if ! error_code=$(jq -r 'if type == "object" and (.error | type == "string") then .error else "unknown_error" end' "$response"); then
    die "$stage failed (HTTP $http_status). Keycloak did not return a JSON error."
  fi
  die "$stage failed (HTTP $http_status): $error_code. Check the Keycloak URL, realm, client, and device authorization settings."
}
device_sign_in() {
  local challenge realm_path device_url token_url interval lifetime deadline remaining limit
  keycloak_url=${keycloak_url:-${ram_url%/}/auth}
  [[ "$keycloak_url" =~ ^https?://[^/?#@]+(/[^?#]*)?$ ]] || die 'The Keycloak base URL is not valid.'
  [[ -n "$keycloak_realm" && -n "$keycloak_client_id" ]] || die 'The Keycloak realm and client ID are required.'
  realm_path=$(printf '%s' "$keycloak_realm" | jq -sRr @uri)
  device_url="${keycloak_url%/}/realms/$realm_path/protocol/openid-connect/auth/device"
  token_url="${keycloak_url%/}/realms/$realm_path/protocol/openid-connect/token"
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n' >"$verifier_file"
  challenge=$(openssl dgst -sha256 -binary <"$verifier_file" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  jq -nrj --arg client "$keycloak_client_id" --arg challenge "$challenge" '
    {client_id:$client,scope:"openid",code_challenge:$challenge,code_challenge_method:"S256"}
    | to_entries | map((.key | @uri) + "=" + (.value | @uri)) | join("&")' >"$form_file"
  printf 'Start RAM device-code sign-in.\n' >&2
  http_request POST "$device_url" "$device_file" "$form_file"
  if [[ "$http_status" != 200 ]]; then oauth_failure 'Device authorization' "$device_file"; fi
  jq -e '
    type == "object" and (.device_code | type == "string" and length > 0)
    and (.user_code | type == "string" and length > 0)
    and (.verification_uri | type == "string" and test("^https?://[^[:space:]]+$"))
    and (.expires_in | type == "number" and . > 0 and . <= 86400 and . == floor)
    and (if has("interval") then (.interval | type == "number" and . >= 1 and . <= 86400 and . == floor) else true end)
    and (if has("verification_uri_complete") then
      (.verification_uri_complete | type == "string" and test("^https?://[^[:space:]]+$")) else true end)
  ' "$device_file" >/dev/null || die 'Keycloak returned an invalid device authorization response.'
  jq -r '"Open this URL in a browser: \(.verification_uri_complete // .verification_uri)\nUser code: \(.user_code)"' "$device_file" >&2
  interval=$(jq '.interval // 5' "$device_file")
  lifetime=$(jq '.expires_in' "$device_file")
  deadline=$((SECONDS + lifetime))
  jq -nrj --arg client "$keycloak_client_id" --slurpfile device "$device_file" --rawfile verifier "$verifier_file" '
    {grant_type:"urn:ietf:params:oauth:grant-type:device_code",client_id:$client,
     device_code:$device[0].device_code,code_verifier:$verifier}
    | to_entries | map((.key | @uri) + "=" + (.value | @uri)) | join("&")' >"$form_file"
  while ((SECONDS < deadline)); do
    remaining=$((deadline - SECONDS))
    if ((interval >= remaining)); then sleep "$remaining"; break; fi
    sleep "$interval"
    remaining=$((deadline - SECONDS))
    if ((remaining <= 0)); then break; fi
    limit=$timeout_seconds
    if ((limit > remaining)); then limit=$remaining; fi
    http_request POST "$token_url" "$token_file" "$form_file" "$limit"
    if [[ "$http_status" == 200 ]]; then
      jq -e 'type == "object" and
        (.access_token | type == "string" and length > 0 and (test("[[:space:]]") | not)) and
        (.expires_in | type == "number" and . > 0)' "$token_file" >/dev/null ||
        die 'Keycloak returned an invalid access token response.'
      jq -r '"Authorization: Bearer \(.access_token)"' "$token_file" >>"$headers_file"
      printf 'RAM sign-in is complete.\n' >&2
      return
    fi
    if [[ "$http_status" == 400 ]]; then
      case "$(jq -r 'if type == "object" then .error // "" else "" end' "$token_file")" in
        authorization_pending) continue ;;
        slow_down) interval=$((interval + 5)); continue ;;
        access_denied) die 'Device authorization was denied.' ;;
        expired_token) die 'The device code expired. Start the script again.' ;;
      esac
    fi
    oauth_failure 'Device token request' "$token_file"
  done
  die 'The device code expired. Start the script again.'
}

printf 'Accept: application/json\n' >"$headers_file"
if [[ -n "${RAM_AUTHORIZATION:-}" ]]; then
  [[ "$RAM_AUTHORIZATION" != *$'\n'* && "$RAM_AUTHORIZATION" != *$'\r'* ]] ||
    die 'The Authorization value must contain one line.'
  printf 'Authorization: %s\n' "$RAM_AUTHORIZATION" >>"$headers_file"
else
  device_sign_in
fi
get_ram_rows() {
  local query=$1 output=$2 offset=0 count
  : >"$output"
  while :; do
    http_request GET "$postgrest_url/$query&limit=100&offset=$offset" "$page_file"
    if [[ "$http_status" != 200 && "$http_status" != 206 ]]; then
      if jq -e 'type == "object" and (.code | type == "string") and (.message | type == "string")' \
        "$page_file" >/dev/null 2>&1; then
        jq -c '{code,message}' "$page_file" >&2
        jq -r 'if .code == "PGRST302" then
          "PostgREST requires a database role. Check token forwarding and jwt-role-claim-key.",
          "An administrator account can receive a token without the required RAM role claim."
          else empty end' "$page_file" >&2
      fi
      die "The RAM API request failed (HTTP $http_status). Check access permissions and token validity."
    fi
    jq -e 'type == "array"' "$page_file" >/dev/null || die 'The RAM API did not return an array.'
    jq -c '.[]' "$page_file" >>"$output"
    count=$(jq 'length' "$page_file")
    if ((count < 100)); then break; fi
    offset=$((offset + 100))
  done
}
get_ram_rows 'agent?select=id,name,description,agent_card&order=name.asc,id.asc' "$definitions_file"
get_ram_rows 'agent_experiment?select=agent_id&status=eq.champion&order=id.asc' "$champions_file"
kube -n "$namespace" get services -l 'sas-retagentmgr/agent-id,dev-server=false' -o json >"$services_file"
kube -n "$namespace" get pods -l 'sas-retagentmgr/workload-type=agent' -o json >"$pods_file"
agents=$(jq -n --slurpfile definitions "$definitions_file" --slurpfile champions "$champions_file" \
  --slurpfile services "$services_file" --slurpfile pods "$pods_file" --arg namespace "$namespace" '
  def strings($fields):
    . as $o | all($fields[]; . as $key | ($o | has($key) | not) or ($o[$key] | type == "string"));
  def string_arrays($fields):
    . as $o | all($fields[]; . as $key | if $o | has($key) then
      ($o[$key] | if type == "array" then all(.[]; type == "string") else false end) else true end);
  def card:
    if type != "object" then false else
      (.name | type == "string" and length > 0)
      and strings(["description", "url", "version", "protocolVersion"])
      and (if has("skills") then (.skills | if type == "array" then all(.[];
        if type == "object" then strings(["id", "name", "description"])
          and string_arrays(["tags", "examples"]) else false end) else false end) else true end)
    end;
  [$definitions[] as $agent |
    [$services[0].items[] | select(
      .metadata.labels["sas-retagentmgr/agent-id"] == $agent.id and
      .metadata.labels["dev-server"] == "false" and .metadata.deletionTimestamp == null and
      ((.spec.selector // {}) | length > 0) and
      any(.spec.ports[]; .port == 8001 and (.protocol == null or .protocol == "TCP"))
    ) | . as $service | select(any($pods[0].items[];
      . as $pod | .metadata.deletionTimestamp == null and .status.phase == "Running" and
      .metadata.labels["sas-retagentmgr/agent-id"] == $agent.id and .metadata.labels["dev-server"] == "false" and
      all($service.spec.selector | to_entries[]; $pod.metadata.labels[.key] == .value) and
      any(.status.conditions[]?; .type == "Ready" and .status == "True")
    ))] as $ready |
    {agentId: $agent.id, name: $agent.name,
     cardName: ($agent.agent_card | if type == "object" then .name else null end),
     service: $ready[0].metadata.name, namespace: $namespace,
     reason: (if ($agent.agent_card | card | not) then "No valid configured agent card."
       elif any($champions[]; .agent_id == $agent.id) | not then "No champion configuration."
       elif ($ready | length) == 0 then "Need a champion configuration running; found 0"
       elif ($ready | length) != 1 then "Expected one ready production A2A Service; found \($ready | length)."
       else null end)}]')
jq -r '.[] | select(.reason != null) | "Skip \(.agentId): \(.reason)"' <<<"$agents" >&2
agents=$(jq '[.[] | select(.reason == null) | del(.reason)]' <<<"$agents")
if $list_only; then jq . <<<"$agents"; exit 0; fi
count=$(jq 'length' <<<"$agents")
((count > 0)) || die 'No running agents have a valid configured card and a champion configuration.'
if [[ -n "$agent_id" ]]; then
  selected=$(jq -c --arg id "$agent_id" '[.[] | select(.agentId == $id)]' <<<"$agents")
  [[ $(jq 'length' <<<"$selected") == 1 ]] || die "Agent $agent_id is not available for exposure."
  selected=$(jq -c '.[0]' <<<"$selected")
else
  printf 'Available agents with valid configured cards:\n' >&2
  jq -r 'to_entries[] | "\(.key + 1). \(.value.name) | \(.value.agentId) | \(.value.service) | \(.value.cardName)"' <<<"$agents" >&2
  select_number 'Select an agent number' "$count"
  selected=$(jq -c --argjson index "$selection" '.[$index]' <<<"$agents")
fi
id=$(jq -r '.agentId' <<<"$selected")
service_name=$(jq -r '.service' <<<"$selected")
[[ ${#id} -le 63 && "$id" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
  die 'The agent ID must be valid as a Kubernetes label and resource name.'
if [[ -z "$mode" ]]; then
  printf '1. NGINX Ingress\n2. Contour HTTPProxy\n' >&2
  select_number 'Select an exposure mode number' 2
  if ((selection == 0)); then mode=ingress; else mode=httpproxy; fi
fi
if [[ -z "$public_base_url" ]]; then
  prompt_required public_base_url 'Public base URL (include the application path)'
  public_base_url_explicit=true
fi
[[ "$public_base_url" =~ ^(https?)://([a-zA-Z0-9.-]+)(:([0-9]+))?(/[^?#]*)?$ ]] ||
  die 'The public base URL must use a DNS host and a default HTTP or HTTPS port.'
scheme=${BASH_REMATCH[1]} host=${BASH_REMATCH[2],,} port=${BASH_REMATCH[4]} path=${BASH_REMATCH[5]}
[[ "$host" != *..* && ! "$host" =~ ^[0-9.]+$ ]] || die 'The public URL host is not valid.'
[[ -z "$port" || "$scheme:$port" == http:80 || "$scheme:$port" == https:443 ]] ||
  die 'Use a default HTTP or HTTPS port.'
path=${path%/}
if [[ -z "$path" ]]; then path=${base_path%/}; fi
[[ -z "$path" || ( "$path" =~ ^/[-a-zA-Z0-9_/]*$ && "$path" != *//* ) ]] ||
  die "The base path must start with '/' and contain only letters, numbers, '_', '-', and '/'."
route_path="$path/a2a/$id"
endpoint_url="$scheme://$host$route_path"
resource_name="retrieval-agent-manager-a2a-$id"
legacy_hash=$(printf '%s' "$id" | sha256sum)
legacy_name="ram-a2a-${legacy_hash:0:12}"
operations='[]'
proxy_checks='[]'
add_operation() { operations=$(printf '%s\n%s\n' "$operations" "$1" | jq -cs '.[0] + [.[1]]'); }
new_resource() {
  jq -n --arg kind "$1" --arg version "$2" --argjson spec "$3" \
    --arg name "$resource_name" --arg namespace "$namespace" --arg id "$id" '
    {apiVersion:$version, kind:$kind, metadata:{name:$name, namespace:$namespace,
      labels:{"ram-extension/a2a-endpoint":"true", "sas-retagentmgr/agent-id":$id,
        "app.kubernetes.io/managed-by":"ram-extension"}}, spec:$spec}'
}
add_create() { add_operation "$(jq -n --argjson resource "$1" '{action:"create",resource:$resource}')"; }
add_patch() {
  add_operation "$(printf '%s\n%s\n' "$1" "$3" | jq -s --arg field "$2" '
    .[0] as $proxy | .[1] as $value |
    {action:"patch",name:$proxy.metadata.name,namespace:$proxy.metadata.namespace,patch:[
      {op:"test",path:"/metadata/resourceVersion",value:$proxy.metadata.resourceVersion},
      {op:"add",path:("/spec/"+$field),value:$value}]}')"
}
route=$(jq -n --arg path "$route_path" --arg service "$service_name" '
  {conditions:[{prefix:$path}],services:[{name:$service,port:8001}],
   pathRewritePolicy:{replacePrefix:[{prefix:$path,replacement:"/"}]}}')
if [[ "$mode" == ingress ]]; then
  ingress_class_name=${ingress_class_name:-nginx}
  existing=null
  for name in "$resource_name" "$legacy_name"; do
    existing=$(get_object ingress "$name" "$namespace")
    if [[ "$existing" != null ]]; then break; fi
  done
  if [[ "$existing" != null ]] && ! $public_base_url_explicit && ! $base_path_explicit; then
    existing_paths=$(jq --arg id "$id" --arg host "$host" --arg service "$service_name" '
      if .metadata.labels["ram-extension/a2a-endpoint"] == "true"
        and .metadata.labels["sas-retagentmgr/agent-id"] == $id then
        [.spec.rules[]? | select(.host == $host) | .http.paths[]? |
          select(.backend.service.name == $service and .backend.service.port.number == 8001) |
          .path | select(type == "string") | select(endswith("/a2a/" + $id + "(/|$)(.*)")) |
          rtrimstr("(/|$)(.*)") | select(test("^/[-a-zA-Z0-9_/]+$"))] | unique
      else [] end
    ' <<<"$existing")
    existing_path_count=$(jq 'length' <<<"$existing_paths")
    ((existing_path_count <= 1)) || die 'The managed Ingress has multiple A2A paths. Supply an explicit public base URL.'
    if ((existing_path_count == 1)); then
      route_path=$(jq -r '.[0]' <<<"$existing_paths")
      endpoint_url="$scheme://$host$route_path"
    fi
  fi
  if [[ "$existing" == null && "$scheme" == https && -z "$tls_secret_name" ]]; then
    prompt_required tls_secret_name "TLS Secret name in namespace $namespace"
  fi
  spec=$(jq -n --arg class "$ingress_class_name" --arg host "$host" --arg path "$route_path" \
    --arg service "$service_name" --arg secret "$tls_secret_name" '
    {ingressClassName:$class,rules:[{host:$host,http:{paths:[{path:($path+"(/|$)(.*)"),
      pathType:"ImplementationSpecific",backend:{service:{name:$service,port:{number:8001}}}}]}}]}
    + if $secret != "" then {tls:[{hosts:[$host],secretName:$secret}]} else {} end')
  resource=$(new_resource Ingress networking.k8s.io/v1 "$spec" | jq '
    .metadata.annotations={"nginx.ingress.kubernetes.io/rewrite-target":"/$2","nginx.ingress.kubernetes.io/use-regex":"true"}')
  if [[ "$existing" == null ]]; then add_create "$resource"
  else
    mismatches=$(jq --argjson expected "$resource" --arg secret "$tls_secret_name" \
      --argjson check_tls "$tls_secret_explicit" '
      . as $actual | $expected.spec.rules[0] as $rule | $rule.http.paths[0] as $path |
      [
        (if .metadata.labels["ram-extension/a2a-endpoint"] != "true"
          or .metadata.labels["sas-retagentmgr/agent-id"] != $expected.metadata.labels["sas-retagentmgr/agent-id"]
          then "The Ingress is not managed for this agent." else empty end),
        (if (.spec.ingressClassName // .metadata.annotations["kubernetes.io/ingress.class"] // "") != $expected.spec.ingressClassName
          then "Ingress class: expected \($expected.spec.ingressClassName); found \(.spec.ingressClassName // .metadata.annotations["kubernetes.io/ingress.class"] // "(unset)")." else empty end),
        ($expected.metadata.annotations | to_entries[] |
          select($actual.metadata.annotations[.key] != .value) |
          "Annotation \(.key): expected \(.value); found \($actual.metadata.annotations[.key] // "(unset)")."),
        (if any(.spec.rules[]?; .host == $rule.host and any(.http.paths[]?;
          .path == $path.path and .backend.service.name == $path.backend.service.name
          and .backend.service.port.number == $path.backend.service.port.number)) then empty else
          "Expected route: \($rule.host)\($path.path) -> \($path.backend.service.name):\($path.backend.service.port.number).",
          (.spec.rules[]? | .host as $host | .http.paths[]? |
            "Existing route: \($host)\(.path) -> \(.backend.service.name):\(.backend.service.port.number // .backend.service.port.name).")
          end),
        (if $check_tls and (any(.spec.tls[]?;
          .secretName == $secret and any(.hosts[]; . == $rule.host)) | not)
          then "The existing Ingress does not use the explicitly requested TLS Secret \($secret) for \($rule.host)." else empty end)
      ]
    ' <<<"$existing")
    if [[ $(jq 'length' <<<"$mismatches") -gt 0 ]]; then
      printf 'Ingress %s/%s does not match the requested endpoint:\n' "$namespace" "$(jq -r '.metadata.name' <<<"$existing")" >&2
      jq -r '.[] | "  - " + .' <<<"$mismatches" >&2
      die 'The existing Ingress was not changed.'
    fi
    printf 'Reuse managed Ingress %s/%s. No Ingress change is required.\n' \
      "$namespace" "$(jq -r '.metadata.name' <<<"$existing")" >&2
  fi
else
  [[ -z "$tls_secret_name" ]] || die 'Contour uses TLS settings from the parent HTTPProxy.'
  parent=$(get_object httpproxy "$http_proxy_name" "$extension_namespace")
  if [[ "$parent" == null ]]; then
    printf 'HTTPProxy %s/%s was not found.\n' "$extension_namespace" "$http_proxy_name" >&2
    prompt_required http_proxy_name "Parent HTTPProxy name in namespace $extension_namespace"
    parent=$(get_object httpproxy "$http_proxy_name" "$extension_namespace")
    [[ "$parent" != null ]] || die "HTTPProxy $extension_namespace/$http_proxy_name was not found."
  fi
  jq -e --arg host "$host" '.spec.virtualhost.fqdn == $host' <<<"$parent" >/dev/null ||
    die 'The public host does not match the parent HTTPProxy virtual host.'
  if [[ "$scheme" == https ]]; then
    jq -e '.spec.virtualhost.tls != null' <<<"$parent" >/dev/null || die 'The parent HTTPProxy has no TLS settings.'
  fi
  matching_routes=$(jq --arg path "$route_path" '[.spec.routes[]? | select(any(.conditions[]?; .prefix == $path))]' <<<"$parent")
  jq -e --argjson route "$route" 'all(.[]; .conditions == $route.conditions and .services == $route.services
    and .pathRewritePolicy.replacePrefix == $route.pathRewritePolicy.replacePrefix)' <<<"$matching_routes" >/dev/null ||
    die 'The HTTPProxy route has different routing. No resource was changed.'
  proxy_checks=$(jq -n --arg name "$http_proxy_name" --arg namespace "$extension_namespace" '[{name:$name,namespace:$namespace}]')
  if [[ "$namespace" == "$extension_namespace" ]]; then
    jq -e '.spec.routes == null or (.spec.routes | type == "array")' <<<"$parent" >/dev/null ||
      die 'The parent HTTPProxy routes field is not an array.'
    if [[ $(jq 'length' <<<"$matching_routes") == 0 ]]; then
      routes=$(jq --argjson route "$route" '.spec.routes + [$route]' <<<"$parent")
      add_patch "$parent" routes "$routes"
    fi
  else
    [[ $(jq 'length' <<<"$matching_routes") == 0 ]] || die 'The agent route already exists in the extension namespace.'
    ingress_class_name=${ingress_class_name:-$(jq -r '.spec.ingressClassName // empty' <<<"$parent")}
    child_spec=$(jq -n --arg class "$ingress_class_name" --argjson route "$route" '
      {routes:[$route]} + if $class != "" then {ingressClassName:$class} else {} end')
    child=null
    for name in "$resource_name" "$legacy_name"; do
      child=$(get_object httpproxy "$name" "$namespace")
      if [[ "$child" != null ]]; then resource_name=$name; break; fi
    done
    if [[ "$child" == null ]]; then add_create "$(new_resource HTTPProxy projectcontour.io/v1 "$child_spec")"
    else
      jq -e --arg id "$id" --arg class "$ingress_class_name" --argjson route "$route" '
        .metadata.labels["ram-extension/a2a-endpoint"] == "true"
        and .metadata.labels["sas-retagentmgr/agent-id"] == $id
        and (.spec.ingressClassName // "") == $class and (.spec | has("virtualhost") | not)
        and (.spec.routes | length == 1) and .spec.routes[0].conditions == $route.conditions
        and .spec.routes[0].services == $route.services
        and .spec.routes[0].pathRewritePolicy.replacePrefix == $route.pathRewritePolicy.replacePrefix
      ' <<<"$child" >/dev/null || die 'The existing child HTTPProxy has different routing. No resource was changed.'
    fi
    includes=$(jq '.spec.includes // []' <<<"$parent")
    matching_includes=$(jq --arg name "$resource_name" --arg namespace "$namespace" '
      [.[] | select(.name == $name and .namespace == $namespace)]' <<<"$includes")
    jq -e 'all(.[]; (.conditions // [] | length) == 0)' <<<"$matching_includes" >/dev/null ||
      die 'The existing HTTPProxy include has conditions. No resource was changed.'
    if [[ $(jq 'length' <<<"$matching_includes") == 0 ]]; then
      includes=$(jq --arg name "$resource_name" --arg namespace "$namespace" '. + [{name:$name,namespace:$namespace}]' <<<"$includes")
      add_patch "$parent" includes "$includes"
    fi
    proxy_checks=$(jq --arg name "$resource_name" --arg namespace "$namespace" '. + [{name:$name,namespace:$namespace}]' <<<"$proxy_checks")
  fi
fi
printf 'Agent: %s; Service: %s/%s:8001\nEndpoint: %s\nAgent card: %s/.well-known/agent-card.json\n' \
  "$id" "$namespace" "$service_name" "$endpoint_url" "$endpoint_url" >&2
if $dry_run; then
  jq . <<<"$operations"
  printf 'DryRun: no resource was changed.\n' >&2
  exit 0
fi
while IFS= read -r operation; do
  if [[ $(jq -r '.action' <<<"$operation") == create ]]; then
    jq '.resource' <<<"$operation" | kube create -f -
  else
    jq '.patch' <<<"$operation" >"$patch_file"
    kube -n "$(jq -r '.namespace' <<<"$operation")" patch httpproxy "$(jq -r '.name' <<<"$operation")" \
      --type=json --patch-file "$patch_file"
  fi
done < <(jq -c '.[]' <<<"$operations")
while IFS= read -r proxy; do
  kube -n "$(jq -r '.namespace' <<<"$proxy")" wait "httpproxy/$(jq -r '.name' <<<"$proxy")" \
    '--for=jsonpath={.status.currentStatus}=valid' "--timeout=${timeout_seconds}s"
done < <(jq -c '.[]' <<<"$proxy_checks")
printf 'The route is configured. Check the public agent card URL before use.\n' >&2
