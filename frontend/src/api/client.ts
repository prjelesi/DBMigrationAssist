import axios from 'axios';

const BASE_URL = import.meta.env.VITE_API_URL ?? '/api';
const API_KEY  = import.meta.env.VITE_API_KEY  ?? '';

const client = axios.create({
  baseURL: BASE_URL,
  headers: {
    'Content-Type': 'application/json',
    ...(API_KEY ? { 'X-API-Key': API_KEY } : {}),
  },
});

export default client;
