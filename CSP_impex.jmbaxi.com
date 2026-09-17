export default {
  async fetch(request, env, ctx) {
    // 1. Fetch the original response from your IIS server
    const response = await fetch(request);
    
    // Only process HTML pages
    const contentType = response.headers.get("content-type");
    if (!contentType || !contentType.includes("text/html")) {
      return response;
    }

    // 2. Generate a random Base64 Nonce
    const nonce = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));

    // 3. Define the new strict CSP with the dynamic nonce attached
    const csp = `default-src 'self'; script-src 'self' 'nonce-${nonce}'; style-src 'self' 'unsafe-inline';`;

    // 4. Create a mutable copy of the response to alter headers
    const newResponse = new Response(response.body, response);
    newResponse.headers.set("content-security-policy-report-only", csp);

    // 5. Use HTMLRewriter to find all <script> tags and inject the nonce attribute
    class ScriptHandler {
      element(element) {
        element.setAttribute("nonce", nonce);
      }
    }

    return new HTMLRewriter()
      .on("script", new ScriptHandler())
      .transform(newResponse);
  }
};
