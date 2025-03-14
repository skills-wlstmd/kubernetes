const express = require("express");
const app = express();
const PORT = 8080;

app.get("/healthcheck", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/v1/worldskills", (req, res) => {
  res.send("Cloud Computing");
});

app.get("/v1/gold", (req, res) => {
  res.send("I want Get Gold Medal!");
});

app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});
