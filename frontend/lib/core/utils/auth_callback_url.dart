/// Query parameters Supabase adds when an OAuth redirect comes back.
const authCallbackParams = {'code', 'error', 'error_code', 'error_description'};

/// [url] without the sign-in callback parameters (keeping the `#/route`), or
/// null when there is nothing to remove.
String? withoutAuthCallbackParams(Uri url) {
  if (!url.queryParameters.keys.any(authCallbackParams.contains)) return null;
  final rest = Map.of(url.queryParameters)..removeWhere((k, _) => authCallbackParams.contains(k));
  final query = rest.isEmpty ? '' : '?${Uri(queryParameters: rest).query}';
  final fragment = url.hasFragment ? '#${url.fragment}' : '';
  return '${url.origin}${url.path}$query$fragment';
}
