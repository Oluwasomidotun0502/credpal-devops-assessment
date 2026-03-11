const express = require('express');
const app = express();

app.use(express.json());

// Root route
app.get('/', (req, res) => res.send('Welcome to CredPal API'));

// API route
app.get('/api', (req, res) => res.json({ message: "CredPal API is running" }));

// Health check
app.get('/health', (req, res) => res.status(200).json({ status: "healthy" }));

// Status endpoint
app.get('/status', (req, res) => res.json({ service: "running", uptime: process.uptime() }));

// Process endpoint
app.post('/process', (req, res) => {
  const data = req.body;
  console.log("Processing:", data);
  res.json({ message: "Data processed", input: data });
});

const PORT = 3000;
app.listen(PORT, () => console.log(`CredPal Node.js app running on port ${PORT}`));
