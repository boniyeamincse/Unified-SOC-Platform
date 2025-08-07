import React, { useState } from 'react';

function App() {
  const [query, setQuery] = useState('');
  const [result, setResult] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setResult('');
    // Replace with your actual AI engine endpoint
    const response = await fetch('http://localhost:11434/investigate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const data = await response.json();
    setResult(data.result || JSON.stringify(data));
    setLoading(false);
  };

  return (
    <div style={{ maxWidth: 600, margin: '40px auto', fontFamily: 'sans-serif' }}>
      <h2>AI-Assisted Investigation</h2>
      <form onSubmit={handleSubmit}>
        <input
          type="text"
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="Enter investigation query..."
          style={{ width: '80%', padding: 8 }}
          required
        />
        <button type="submit" style={{ padding: 8, marginLeft: 8 }} disabled={loading}>
          {loading ? 'Investigating...' : 'Investigate'}
        </button>
      </form>
      {result && (
        <div style={{ marginTop: 24, background: '#f4f4f4', padding: 16, borderRadius: 8 }}>
          <strong>Result:</strong>
          <pre>{result}</pre>
        </div>
      )}
    </div>
  );
}

export default App;
