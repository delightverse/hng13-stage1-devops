const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
    const response = {
        message: 'HNG Stage 1 - Automated Deployment Success!',
        hostname: os.hostname(),
        timestamp: new Date().toISOString(),
        environment: process.env.NODE_ENV || 'production',
        port: PORT,
        path: req.url
    };
    
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(response, null, 2));
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'production'}`);
});