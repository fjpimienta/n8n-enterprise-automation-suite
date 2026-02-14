import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AuthService } from '@core/services/auth.service';
import { AiChatComponent } from '@features/ai-assistant/components/ai-chat/ai-chat.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, AiChatComponent],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})
export class AppComponent {
  authService = inject(AuthService);
  title = 'Hotel Manager';
}