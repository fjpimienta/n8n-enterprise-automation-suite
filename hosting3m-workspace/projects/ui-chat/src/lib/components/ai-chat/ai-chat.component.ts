import { Component, inject, signal, ElementRef, ViewChild, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AiService } from '../../services/ai.service';
import { CHAT_CONFIG_TOKEN } from '../../tokens/chat.token';

@Component({
  selector: 'lib-ai-chat',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './ai-chat.component.html',
  styleUrls: ['./ai-chat.component.css']
})
export class AiChatComponent {
  public config = inject(CHAT_CONFIG_TOKEN);
  public aiService = inject(AiService);

  isOpen = signal(false);
  userInput = '';

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

  send() {
    this.aiService.sendMessage(this.userInput);
    this.userInput = '';
  }

  private scrollToBottom(): void {
    if (this.scrollContainer) {
      try {
        this.scrollContainer.nativeElement.scrollTop = this.scrollContainer.nativeElement.scrollHeight;
      } catch (err) { }
    }
  }
}