using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddEvidenceDatabaseTag : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "DatabaseId",
                schema: "assessment",
                table: "uploaded_report",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_uploaded_report_DatabaseId",
                schema: "assessment",
                table: "uploaded_report",
                column: "DatabaseId");

            migrationBuilder.AddForeignKey(
                name: "FK_uploaded_report_database_instance_DatabaseId",
                schema: "assessment",
                table: "uploaded_report",
                column: "DatabaseId",
                principalSchema: "inventory",
                principalTable: "database_instance",
                principalColumn: "DatabaseId",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_uploaded_report_database_instance_DatabaseId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropIndex(
                name: "IX_uploaded_report_DatabaseId",
                schema: "assessment",
                table: "uploaded_report");

            migrationBuilder.DropColumn(
                name: "DatabaseId",
                schema: "assessment",
                table: "uploaded_report");
        }
    }
}
