import { AIProvider } from './ai-provider.js';

export class FakeAIProvider extends AIProvider {
  constructor({ response, error } = {}) {
    super();
    this.response = response;
    this.error = error;
    this.requests = [];
  }

  async generateStructuredAnalysis(request) {
    this.requests.push(request);
    if (this.error) throw this.error;
    return structuredClone(this.response);
  }
}
