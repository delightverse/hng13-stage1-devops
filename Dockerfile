FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy application files
COPY app.js .

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); });"

# Run application
CMD ["node", "app.js"]