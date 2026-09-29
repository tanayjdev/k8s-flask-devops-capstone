wait_for_pod_count() {
  local label=$1
  local count=$2
  while [ "$(kubectl get pods -l "$label" --no-headers 2>/dev/null | wc -l)" -ne "$count" ]; do sleep 1; done
}
wait_for_service_ready_endpoint() {
  local svc=$1
  while ! kubectl get endpointslices -l kubernetes.io/service-name="$svc" -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -q "true"; do sleep 1; done
}
wait_for_service_no_ready_endpoints() {
  local svc=$1
  while kubectl get endpointslices -l kubernetes.io/service-name="$svc" -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -q "true"; do sleep 1; done
}
