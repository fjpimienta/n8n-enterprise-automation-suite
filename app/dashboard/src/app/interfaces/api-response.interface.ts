// models/api-response.interface.ts
export interface ApiResponse<T> {
  error: boolean;
  operation: string;
  data: T[];     // Aquí es donde viven tus habitaciones
  meta?: any;
}