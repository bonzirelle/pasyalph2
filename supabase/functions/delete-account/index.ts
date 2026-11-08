import { handleRequest } from './handler.js';
Deno.serve((request) => handleRequest(request));
