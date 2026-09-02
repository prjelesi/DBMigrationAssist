using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddQuestionnaireDatabaseScope : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_response_ProjectId_TemplateId",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.AddColumn<Guid>(
                name: "DatabaseId",
                schema: "questionnaire",
                table: "response",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_response_DatabaseId",
                schema: "questionnaire",
                table: "response",
                column: "DatabaseId");

            migrationBuilder.CreateIndex(
                name: "IX_response_ProjectId_DatabaseId_TemplateId_database",
                schema: "questionnaire",
                table: "response",
                columns: new[] { "ProjectId", "DatabaseId", "TemplateId" },
                unique: true,
                filter: "\"DatabaseId\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_response_ProjectId_TemplateId_project",
                schema: "questionnaire",
                table: "response",
                columns: new[] { "ProjectId", "TemplateId" },
                unique: true,
                filter: "\"DatabaseId\" IS NULL");

            migrationBuilder.AddForeignKey(
                name: "FK_response_database_instance_DatabaseId",
                schema: "questionnaire",
                table: "response",
                column: "DatabaseId",
                principalSchema: "inventory",
                principalTable: "database_instance",
                principalColumn: "DatabaseId",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_response_database_instance_DatabaseId",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.DropIndex(
                name: "IX_response_DatabaseId",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.DropIndex(
                name: "IX_response_ProjectId_DatabaseId_TemplateId_database",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.DropIndex(
                name: "IX_response_ProjectId_TemplateId_project",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.DropColumn(
                name: "DatabaseId",
                schema: "questionnaire",
                table: "response");

            migrationBuilder.CreateIndex(
                name: "IX_response_ProjectId_TemplateId",
                schema: "questionnaire",
                table: "response",
                columns: new[] { "ProjectId", "TemplateId" });
        }
    }
}
