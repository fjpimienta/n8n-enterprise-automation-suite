import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AuthService } from '@core/services/auth.service';
<<<<<<< HEAD:hosting3m-workspace/projects/dashboard/src/app/app.component.ts
import { AiChatComponent } from 'ui-chat';
=======
import { AiChatComponent } from '@features/ai-assistant/components/ai-chat/ai-chat.component';
>>>>>>> origin/develop:app/dashboard/src/app/app.component.ts

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