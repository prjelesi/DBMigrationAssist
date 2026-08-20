using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class RepairEvidenceBundleSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "EvidenceBundleId",
                schema: "reporting",
                table: "generated_report",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "evidence_bundle",
                schema: "reporting",
                columns: table => new
                {
                    EvidenceBundleId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    BundleJson = table.Column<string>(type: "jsonb", nullable: false),
                    ContentHash = table.Column<string>(type: "text", nullable: false),
                    CreatedBy = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_evidence_bundle", x => x.EvidenceBundleId);
                    table.ForeignKey(
                        name: "FK_evidence_bundle_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.Sql(
                """
                INSERT INTO reporting.evidence_bundle
                    ("EvidenceBundleId", "ProjectId", "BundleJson", "ContentHash", "CreatedBy", "CreatedAt")
                SELECT
                    "GeneratedReportId", "ProjectId", '{}'::jsonb,
                    'legacy-' || "GeneratedReportId"::text, "GeneratedBy", "GeneratedAt"
                FROM reporting.generated_report;

                UPDATE reporting.generated_report
                SET "EvidenceBundleId" = "GeneratedReportId"
                WHERE "EvidenceBundleId" IS NULL;
                """);

            migrationBuilder.AlterColumn<Guid>(
                name: "EvidenceBundleId",
                schema: "reporting",
                table: "generated_report",
                type: "uuid",
                nullable: false,
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_generated_report_EvidenceBundleId",
                schema: "reporting",
                table: "generated_report",
                column: "EvidenceBundleId");

            migrationBuilder.CreateIndex(
                name: "IX_evidence_bundle_ContentHash",
                schema: "reporting",
                table: "evidence_bundle",
                column: "ContentHash");

            migrationBuilder.CreateIndex(
                name: "IX_evidence_bundle_ProjectId_CreatedAt",
                schema: "reporting",
                table: "evidence_bundle",
                columns: new[] { "ProjectId", "CreatedAt" });

            migrationBuilder.AddForeignKey(
                name: "FK_generated_report_evidence_bundle_EvidenceBundleId",
                schema: "reporting",
                table: "generated_report",
                column: "EvidenceBundleId",
                principalSchema: "reporting",
                principalTable: "evidence_bundle",
                principalColumn: "EvidenceBundleId",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_generated_report_evidence_bundle_EvidenceBundleId",
                schema: "reporting",
                table: "generated_report");

            migrationBuilder.DropTable(
                name: "evidence_bundle",
                schema: "reporting");

            migrationBuilder.DropIndex(
                name: "IX_generated_report_EvidenceBundleId",
                schema: "reporting",
                table: "generated_report");

            migrationBuilder.DropColumn(
                name: "EvidenceBundleId",
                schema: "reporting",
                table: "generated_report");
        }
    }
}
