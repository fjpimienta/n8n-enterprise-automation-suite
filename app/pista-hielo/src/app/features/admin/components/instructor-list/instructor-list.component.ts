import { Component, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { InstructorService } from '@features/admin/services/instructor.service';

@Component({
  selector: 'app-instructor-list',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './instructor-list.component.html',
  styles: ['./instructor-list.component.css']
})
export class InstructorListComponent implements OnInit {

  public instructorService = inject(InstructorService);

  ngOnInit() {
    this.instructorService.loadInstructors();
  }
}