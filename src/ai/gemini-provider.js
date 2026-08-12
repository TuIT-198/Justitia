import { AIProvider } from './ai-provider.js';

export class AIProviderConfigurationError extends Error {}

export class GeminiProvider extends AIProvider {
  constructor({ apiKey = process.env.GEMINI_API_KEY, model = process.env.GEMINI_MODEL, fetchImpl = globalThis.fetch } = {}) {
    super();
    this.apiKey = apiKey;
    this.model = model;
    this.fetchImpl = fetchImpl;
  }

  async generateStructuredAnalysis({ context }) {
    if (!this.apiKey || !this.model) {
      throw new AIProviderConfigurationError('GEMINI_API_KEY and GEMINI_MODEL are required for real AI calls');
    }
    if (typeof this.fetchImpl !== 'function') {
      throw new AIProviderConfigurationError('A fetch implementation is required');
    }

    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(this.model)}:generateContent`;
    const response = await this.fetchImpl(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': this.apiKey
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: 'Return only the requested JSON contract. Do not return an overall result or hidden reasoning.' }]
        },
        contents: [{ role: 'user', parts: [{ text: JSON.stringify(context) }] }],
        generationConfig: { responseMimeType: 'application/json' }
      })
    });

    if (!response.ok) {
      throw new Error(`Gemini request failed with HTTP ${response.status}`);
    }
    const payload = await response.json();
    const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== 'string') throw new Error('Gemini response did not contain JSON text');
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }
}
