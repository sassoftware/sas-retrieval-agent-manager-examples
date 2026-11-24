const http = require("node:http");
const zlib = require("node:zlib");
const next = require("next");
const { loadEnvConfig } = require("@next/env");

const dev = process.env.NODE_ENV === "development";
// Custom servers don't get Next's automatic .env loading that `next dev`/`next
// build` provide — load it explicitly (and before reading
// NEXT_PUBLIC_BASE_PATH below) so `.env`/`.env.local` values are honored here too.
loadEnvConfig(process.cwd(), dev);

function normalizeBasePath(value) {
  const trimmed = (value || "").trim().replace(/\/+$/, "");
  if (!trimmed) return "";
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
}

const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH);
const port = Number(process.env.PORT || 3000);
const app = next({ dev });
const handle = app.getRequestHandler();

function handleWithRuntimeBasePath(request, response) {
  const chunks = [];
  const write = response.write.bind(response);
  const writeHead = response.writeHead.bind(response);
  const end = response.end.bind(response);
  let headArgs;
  response.writeHead = (...args) => {
    headArgs = args;
    return response;
  };
  response.write = (chunk, encoding, callback) => {
    if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding));
    if (callback) callback();
    return true;
  };
  response.end = (chunk, encoding, callback) => {
    if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding));
    const contentType = response.getHeader("content-type");
    const contentEncoding = response.getHeader("content-encoding");
    let body = Buffer.concat(chunks);
    if (typeof contentType === "string" && /(?:css|html|javascript|json)/.test(contentType)) {
      if (contentEncoding === "gzip") body = zlib.gunzipSync(body);
      if (contentEncoding === "br") body = zlib.brotliDecompressSync(body);
      if (contentEncoding === "deflate") body = zlib.inflateSync(body);

      let text = body.toString("utf8").replace(
        /(?<![A-Za-z0-9._-])\/_next\//g,
        `${basePath}/_next/`,
      );
      // Only inject the `data-base-path` attribute into actual HTML documents.
      // This same text pipeline also runs over JS/CSS/JSON responses (to
      // rewrite `/_next/` asset references in them), and some of those —
      // notably React's dev-mode bundle, which contains the literal string
      // `<html>` inside a warning message — can otherwise have this regex
      // match unrelated text and inject an unescaped `"` into an
      // already-escaped JS string literal, corrupting the script.
      if (/html/.test(contentType)) {
        text = text.replace(
          /<html([^>]*)>/,
          (_match, attrs) => `<html${attrs} data-base-path="${basePath}">`,
        );
      }
      body = Buffer.from(text, "utf8");

      if (contentEncoding === "gzip") body = zlib.gzipSync(body);
      if (contentEncoding === "br") body = zlib.brotliCompressSync(body);
      if (contentEncoding === "deflate") body = zlib.deflateSync(body);
      response.removeHeader("content-length");
    }
    const linkHeader = response.getHeader("link");
    if (linkHeader) {
      const prefixLink = (value) => value.replace(
        /(?<![A-Za-z0-9._-])\/_next\//g,
        `${basePath}/_next/`,
      );
      response.setHeader(
        "link",
        Array.isArray(linkHeader) ? linkHeader.map(prefixLink) : prefixLink(String(linkHeader)),
      );
    }
    response.writeHead = writeHead;
    response.write = write;
    response.end = end;
    if (headArgs) writeHead(...headArgs);
    end(body, callback);
  };
  handle(request, response);
}

app.prepare().then(() => {
  http.createServer((request, response) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (basePath && pathname !== basePath && !pathname.startsWith(`${basePath}/`)) {
      response.statusCode = 404;
      response.end("Not Found");
      return;
    }
    if (basePath) {
      request.url = request.url.slice(basePath.length) || "/";
    }
    handleWithRuntimeBasePath(request, response);
  }).listen(port, () => {
    console.log(`Ready on port ${port}`);
  });
});
