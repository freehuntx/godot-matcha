const http = require("http")
const url = require("url")
const path = require("path")
const fs = require("fs")

const SET_COI_HEADER = true
const PORT = 8080;
const PUBLIC_FOLDER = __dirname + "/export/web"

const server = http.createServer((request, response) => {
  const uri = url.parse(request.url).pathname
  let filename = path.join(PUBLIC_FOLDER, uri)

  if (!fs.existsSync(filename)) {
    response.writeHead(404, { "Content-Type": "text/plain" })
    response.write("404 Not Found")
    response.end()
    return
  }

  if (fs.statSync(filename).isDirectory()) filename += '/index.html'

  if (!fs.existsSync(filename)) {
    response.writeHead(404, { "Content-Type": "text/plain" })
    response.write("404 Not Found")
    response.end()
    return
  }

  try {
    const file = fs.readFileSync(filename, "binary")

    if (SET_COI_HEADER) {
      response.setHeader("Cross-Origin-Opener-Policy", "same-origin")
      response.setHeader("Cross-Origin-Opener-Policy-Report-Only", "same-origin")
      response.setHeader("Cross-Origin-Embedder-Policy", "require-corp")  
    }

    if (/\.js$/.test(filename)) {
      response.setHeader("Content-Type", "application/javascript")
    }

    response.writeHead(200);
    response.write(file, "binary");
    response.end();
  } catch (error) {
    response.writeHead(500, {"Content-Type": "text/plain"})
    response.write(error)
    response.end()
    return
  }
})

server.listen(PORT, () => {
  console.log(`HTTP server started: http://127.0.0.1:${PORT}`)
})
