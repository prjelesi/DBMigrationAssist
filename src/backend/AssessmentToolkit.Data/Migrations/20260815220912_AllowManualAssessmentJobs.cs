using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class AllowManualAssessmentJobs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_assessment_job_agent_AgentId",
                schema: "assessment",
                table: "assessment_job");

            migrationBuilder.AlterColumn<Guid>(
                name: "AgentId",
                schema: "assessment",
                table: "assessment_job",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.AddForeignKey(
                name: "FK_assessment_job_agent_AgentId",
                schema: "assessment",
                table: "assessment_job",
                column: "AgentId",
                principalSchema: "assessment",
                principalTable: "agent",
                principalColumn: "AgentId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_assessment_job_agent_AgentId",
                schema: "assessment",
                table: "assessment_job");

            migrationBuilder.AlterColumn<Guid>(
                name: "AgentId",
                schema: "assessment",
                table: "assessment_job",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.AddForeignKey(
                name: "FK_assessment_job_agent_AgentId",
                schema: "assessment",
                table: "assessment_job",
                column: "AgentId",
                principalSchema: "assessment",
                principalTable: "agent",
                principalColumn: "AgentId",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
