import { Component, inject, signal, ElementRef, ViewChild, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AiService } from '../../services/ai.service';

@Component({
  selector: 'app-ai-chat',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './ai-chat.component.html',
  styleUrls: ['./ai-chat.component.css']
})
export class AiChatComponent {
  aiService = inject(AiService);

  isOpen = signal(false);
  userInput = '';

  @ViewChild('scrollContainer') private scrollContainer!: ElementRef;

  constructor() {
    // Auto-scroll al fondo cuando llegan mensajes nuevos
    effect(() => {
      const msgs = this.aiService.messages();
      setTimeout(() => this.scrollToBottom(), 100);
    });
  }

  toggleChat() {
    this.isOpen.update(v => !v);
  }

  send() {
    this.aiService.sendMessage(this.userInput);
    this.userInput = '';
  }

  private scrollToBottom(): void {
    try {
      this.scrollContainer.nativeElement.scrollTop = this.scrollContainer.nativeElement.scrollHeight;
    } catch (err) { }
  }
}