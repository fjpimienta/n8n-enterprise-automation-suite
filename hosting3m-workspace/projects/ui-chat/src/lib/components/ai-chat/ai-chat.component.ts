import { Component, inject, signal, ElementRef, ViewChild, effect, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AiService } from '../../services/ai.service';
import { CHAT_CONFIG_TOKEN } from '../../tokens/chat.token';
import { checkAttachment, resolveAttachmentsConfig, sanitizeFileName } from '../../utils/attachment.util';

@Component({
  selector: 'lib-ai-chat',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './ai-chat.component.html',
  styleUrls: ['./ai-chat.component.css']
})
export class AiChatComponent implements OnDestroy {
  public config = inject(CHAT_CONFIG_TOKEN);
  public aiService = inject(AiService);

  isOpen = signal(false);
  userInput = '';

  readonly attachments = resolveAttachmentsConfig(this.config.attachments);
  readonly acceptAttr = this.attachments.accept.join(',');
  readonly maxSizeLabel = `${+(this.attachments.maxBytes / (1024 * 1024)).toFixed(2)} MB`;

  /** The File reference only (no content is read until the request is built). */
  selectedFile = signal<File | null>(null);
  previewUrl = signal<string | null>(null);
  attachmentError = signal<string | null>(null);
  private destroyed = false;

  @ViewChild('scrollContainer') private scrollContainer!: ElementRef;

  constructor() {
    effect(() => {
      const msgs = this.aiService.messages();
      setTimeout(() => this.scrollToBottom(), 100);
    });
  }

  toggleChat() {
    this.isOpen.update(v => !v);
  }

  async send() {
    const file = this.selectedFile();
    if (!file) {
      this.aiService.sendMessage(this.userInput);
      this.userInput = '';
      return;
    }

    const text = this.userInput;
    this.userInput = '';
    this.clearFile(); // revokes the preview URL on send
    const delivered = await this.aiService.sendMessage(text, file);
    if (!delivered && !this.destroyed) {
      // Keep the draft and the file so the user can retry.
      if (!this.userInput) this.userInput = text;
      if (!this.selectedFile()) this.selectFile(file);
    }
  }

  onFileSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = ''; // allows re-picking the same file
    if (!file) return;

    const check = checkAttachment(file, this.attachments);
    if (!check.ok) {
      this.attachmentError.set(
        check.reason === 'size' ? `El archivo excede el límite de ${this.maxSizeLabel}.`
        : check.reason === 'empty' ? 'El archivo está vacío.'
        : 'Tipo de archivo no permitido.'
      );
      return;
    }
    this.selectFile(file);
  }

  removeFile() {
    this.clearFile();
    this.attachmentError.set(null);
  }

  displayName(file: { name: string }): string {
    return sanitizeFileName(file.name);
  }

  isImage(type: string): boolean {
    return type.startsWith('image/');
  }

  /** Effective type for display (selected files were already validated). */
  selectedType(): string {
    const file = this.selectedFile();
    if (!file) return '';
    const check = checkAttachment(file, this.attachments);
    return check.ok ? check.type : '';
  }

  ngOnDestroy() {
    this.destroyed = true;
    this.revokePreview();
  }

  private selectFile(file: File) {
    this.revokePreview();
    this.attachmentError.set(null);
    this.selectedFile.set(file);
    const check = checkAttachment(file, this.attachments);
    if (check.ok && this.isImage(check.type)) this.previewUrl.set(URL.createObjectURL(file));
  }

  private clearFile() {
    this.revokePreview();
    this.selectedFile.set(null);
  }

  private revokePreview() {
    const url = this.previewUrl();
    if (url) URL.revokeObjectURL(url);
    this.previewUrl.set(null);
  }

  private scrollToBottom(): void {
    if (this.scrollContainer) {
      try {
        this.scrollContainer.nativeElement.scrollTop = this.scrollContainer.nativeElement.scrollHeight;
      } catch (err) { }
    }
  }
}