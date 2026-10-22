#!/usr/bin/env bash
# Build the image. Run the A2A exposure script in the container.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
image_name=${RAM_A2A_IMAGE:-ram-a2a-expose:local}
kubeconfig=${KUBECONFIG_PATH:-${KUBECONFIG:-${HOME}/.kube/config}}
context=
ca_cert=${RAM_CA_CERT:-}
arguments=()

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --kubeconfig | --context | --ca-cert)
      [[ -n "${2:-}" ]] || die "$1 requires a value."
      case "$1" in
        --kubeconfig) kubeconfig=$2 ;;
        --context) context=$2 ;;
        --ca-cert) ca_cert=$2 ;;
      esac
      shift 2 ;;
    --help | -h)
      printf 'Host options: --kubeconfig FILE, --context NAME, --ca-cert FILE. Set RAM_A2A_IMAGE to change the image name.\n'
      bash "$script_dir/expose-a2a.sh" --help
      exit 0 ;;
    *) arguments+=("$1"); shift ;;
  esac
done
for executable in docker kubectl jq; do
  command -v "$executable" >/dev/null || die "$executable is required."
done
[[ -f "$kubeconfig" ]] || die 'Use one existing Kubernetes configuration file.'
if [[ -n "$ca_cert" ]]; then
  [[ -f "$ca_cert" && -r "$ca_cert" ]] || die 'The CA certificate bundle must be a readable file.'
  ca_cert=$(cd "$(dirname "$ca_cert")" && printf '%s/%s' "$(pwd)" "$(basename "$ca_cert")")
fi
if [[ -z "$context" ]]; then
  context_names=$(kubectl --kubeconfig "$kubeconfig" config get-contexts -o name)
  [[ -n "$context_names" ]] || die 'No Kubernetes contexts are available.'
  mapfile -t contexts <<<"$context_names"
  if ((${#contexts[@]} == 1)); then
    context=${contexts[0]}
  else
    for i in "${!contexts[@]}"; do printf '%s. %s\n' "$((i + 1))" "${contexts[$i]}"; done
    while :; do
      read -r -p 'Select a Kubernetes context number: ' number ||
        die 'A context selection is required. Supply --context when input is not available.'
      if [[ "$number" =~ ^[1-9][0-9]{0,5}$ ]] && ((number <= ${#contexts[@]})); then break; fi
      printf 'The selection is not valid. Select a number from the list.\n' >&2
    done
    context=${contexts[$((number - 1))]}
  fi
fi
docker info >/dev/null 2>&1 || die 'Docker is not available.'

umask 077
temporary_directory=$(mktemp -d)
raw_config="$temporary_directory/raw-config.json"
runtime_config="$temporary_directory/config.json"
runtime_token="$temporary_directory/token"
trap 'rm -f -- "$raw_config" "$runtime_config" "$runtime_token"; rmdir -- "$temporary_directory"' EXIT
kubectl --kubeconfig "$kubeconfig" --context "$context" config view --raw --flatten --minify -o json >"$raw_config"
jq -e --arg context "$context" '.contexts | length == 1 and .[0].name == $context' "$raw_config" >/dev/null ||
  die 'The Kubernetes configuration does not match the selected context.'
exec_command=$(jq -r '.users[0].user.exec.command // empty' "$raw_config")
if [[ -n "$exec_command" ]]; then
  [[ "${exec_command##*/}" == kubelogin ]] || die "The container cannot run Kubernetes login command $exec_command."
  login_mode=$(jq -r '
    (.users[0].user.exec.args // []) as $args | ($args | index("--login")) as $index
    | if $index == null then "" else $args[$index + 1] end' "$raw_config")
  if [[ "$login_mode" == azurecli ]]; then
    for executable in az kubelogin; do
      command -v "$executable" >/dev/null || die "$executable is required for this context."
    done
    mapfile -t login_args < <(jq -r '.users[0].user.exec.args[]' "$raw_config")
    kubelogin "${login_args[@]}" | jq -er '.status.token | select(type == "string" and length > 0)' >"$runtime_token"
    jq --rawfile token "$runtime_token" '
      .users[0].user |= (del(.exec, ."auth-provider") + {token: ($token | gsub("[\\r\\n]"; ""))})
    ' "$raw_config" >"$runtime_config"
  else
    jq '.users[0].user.exec.command = "kubelogin"' "$raw_config" >"$runtime_config"
  fi
else
  cp "$raw_config" "$runtime_config"
fi

docker build --tag "$image_name" "$script_dir"
run_arguments=(run --rm --interactive --network host)
if [[ -t 0 && -t 1 ]]; then run_arguments+=(--tty); fi
run_arguments+=(--volume "$runtime_config:/root/.kube/config:ro" --env KUBECONFIG=/root/.kube/config)
if [[ -n "$ca_cert" ]]; then
  run_arguments+=(--volume "$ca_cert:/opt/ram-a2a/ca.pem:ro")
  arguments+=(--ca-cert /opt/ram-a2a/ca.pem)
fi
for variable in RAM_AUTHORIZATION HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
  if [[ -v "$variable" ]]; then run_arguments+=(--env "$variable"); fi
done
docker "${run_arguments[@]}" "$image_name" --context "$context" "${arguments[@]}"
