export interface ApiResponse<T> {
  error: boolean;
  operation: string;
  data: T[];
  meta?: any;
  message: string;
}