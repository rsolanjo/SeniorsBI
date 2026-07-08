// SeniorsBI — servidor estático local (dev preview)
const http = require('http')
const fs   = require('fs')
const path = require('path')
const PORT = 5180
const ROOT = path.join(__dirname, 'dashboard')
const MIME = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.json':'application/json', '.svg':'image/svg+xml', '.png':'image/png' }

http.createServer((req, res) => {
  let url = req.url.split('?')[0]
  if (url === '/') url = '/index.html'
  const fp = path.join(ROOT, url)
  if (!fs.existsSync(fp)) { res.writeHead(404); res.end('Not found'); return }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'text/plain', 'Cache-Control': 'no-cache', 'Access-Control-Allow-Origin': '*' })
  fs.createReadStream(fp).pipe(res)
}).listen(PORT, () => console.log('SeniorsBI serving on http://localhost:' + PORT))
