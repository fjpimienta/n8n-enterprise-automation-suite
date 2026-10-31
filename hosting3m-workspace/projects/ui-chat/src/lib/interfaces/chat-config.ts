export interface ChatAttachmentsConfig {
    /** Shows the paperclip and allows sending one file per message. Default: false. */
    enabled?: boolean;
    /** Client-side size limit in MB. Capped at the 5 MB hard limit. Default: 5. */
    maxSizeMb?: number;
    /** Allowed MIME types. Default: JPEG, PNG, WebP, PDF and XML. */
    accept?: string[];
}

export interface ChatConfig {
    apiUrl_ai: string;
    logoUrl: string;
    title: string;
    primaryColor: string;
    /** Optional. Omitting it keeps the chat text-only, exactly as before. */
    attachments?: ChatAttachmentsConfig;
}
