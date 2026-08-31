using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    [DbContext(typeof(AssessmentDbContext))]
    [Migration("20260830213000_AddDatabaseScopedReports")]
    public partial class AddDatabaseScopedReports : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "DatabaseId",
                schema: "reporting",
                table: "generated_report",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_generated_report_DatabaseId_GeneratedAt",
                schema: "reporting",
                table: "generated_report",
                columns: new[] { "DatabaseId", "GeneratedAt" });

            migrationBuilder.AddForeignKey(
                name: "FK_generated_report_database_instance_DatabaseId",
                schema: "reporting",
                table: "generated_report",
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
                name: "FK_generated_report_database_instance_DatabaseId",
                schema: "reporting",
                table: "generated_report");

            migrationBuilder.DropIndex(
                name: "IX_generated_report_DatabaseId_GeneratedAt",
                schema: "reporting",
                table: "generated_report");

            migrationBuilder.DropColumn(
                name: "DatabaseId",
                schema: "reporting",
                table: "generated_report");
        }
    }
}
