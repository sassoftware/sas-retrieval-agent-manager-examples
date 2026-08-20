const http = require("node:http");
const zlib = require("node:zlib");
const next = require("next");

const basePath = (process.env.NEXT_PUBLIC_BASE_PATH || "").replace(/\/+$/, "");
const port = Number(process.env.PORT || 3000);
const app = next({ dev: false });
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

      const text = body.toString("utf8").replace(
        /(?<![A-Za-z0-9._-])\/_next\//g,
        `${basePath}/_next/`,
      ).replace(
        /<html([^>]*)>/,
        (_match, attrs) => `<html${attrs} data-base-path="${basePath}">`,
      );
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
