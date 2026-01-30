import { Component, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { ClientService } from '@features/admin/services/client.service';

@Component({
  selector: 'app-client-list',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './client-list.component.html',
  styleUrls: ['./client-list.component.css']
})
export class ClientListComponent implements OnInit {
  // Hacemos público el servicio para usarlo en el HTML
  public clientService = inject(ClientService);

  ngOnInit() {
    this.clientService.loadStudents();
  }

  // Método helper para devolver clase de color según estatus
  getStatusBadge(status: string): string {
    switch (status) {
      case 'ACT': return 'bg-success';
      case 'INA': return 'bg-secondary';
      case 'SUSPENDIDO': return 'bg-danger';
      default: return 'bg-secondary';
    }
  }
}