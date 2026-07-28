using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AssessmentToolkit.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "assessment");

            migrationBuilder.EnsureSchema(
                name: "core");

            migrationBuilder.EnsureSchema(
                name: "inventory");

            migrationBuilder.CreateTable(
                name: "customer",
                schema: "core",
                columns: table => new
                {
                    CustomerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Industry = table.Column<string>(type: "text", nullable: true),
                    Region = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_customer", x => x.CustomerId);
                });

            migrationBuilder.CreateTable(
                name: "project",
                schema: "core",
                columns: table => new
                {
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    CustomerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    DeploymentMode = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<string>(type: "text", nullable: false),
                    CreatedBy = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_project", x => x.ProjectId);
                    table.ForeignKey(
                        name: "FK_project_customer_CustomerId",
                        column: x => x.CustomerId,
                        principalSchema: "core",
                        principalTable: "customer",
                        principalColumn: "CustomerId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "environment",
                schema: "core",
                columns: table => new
                {
                    EnvironmentId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Type = table.Column<string>(type: "text", nullable: false),
                    Location = table.Column<string>(type: "text", nullable: true),
                    ConnectivityZone = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_environment", x => x.EnvironmentId);
                    table.ForeignKey(
                        name: "FK_environment_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "agent",
                schema: "assessment",
                columns: table => new
                {
                    AgentId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    EnvironmentId = table.Column<Guid>(type: "uuid", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    PskMode = table.Column<int>(type: "integer", nullable: false),
                    PskHash = table.Column<string>(type: "text", nullable: false),
                    PskSalt = table.Column<string>(type: "text", nullable: false),
                    AllowedPlugins = table.Column<List<string>>(type: "jsonb", nullable: false),
                    LastHeartbeatAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    PskIssuedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_agent", x => x.AgentId);
                    table.ForeignKey(
                        name: "FK_agent_environment_EnvironmentId",
                        column: x => x.EnvironmentId,
                        principalSchema: "core",
                        principalTable: "environment",
                        principalColumn: "EnvironmentId");
                    table.ForeignKey(
                        name: "FK_agent_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "database_instance",
                schema: "inventory",
                columns: table => new
                {
                    DatabaseId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: false),
                    EnvironmentId = table.Column<Guid>(type: "uuid", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Engine = table.Column<int>(type: "integer", nullable: false),
                    Version = table.Column<string>(type: "text", nullable: true),
                    HostName = table.Column<string>(type: "text", nullable: true),
                    Port = table.Column<int>(type: "integer", nullable: true),
                    Criticality = table.Column<int>(type: "integer", nullable: false),
                    OwnerName = table.Column<string>(type: "text", nullable: true),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_database_instance", x => x.DatabaseId);
                    table.ForeignKey(
                        name: "FK_database_instance_environment_EnvironmentId",
                        column: x => x.EnvironmentId,
                        principalSchema: "core",
                        principalTable: "environment",
                        principalColumn: "EnvironmentId");
                    table.ForeignKey(
                        name: "FK_database_instance_project_ProjectId",
                        column: x => x.ProjectId,
                        principalSchema: "core",
                        principalTable: "project",
                        principalColumn: "ProjectId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "assessment_job",
                schema: "assessment",
                columns: table => new
                {
                    JobId = table.Column<Guid>(type: "uuid", nullable: false),
                    AgentId = table.Column<Guid>(type: "uuid", nullable: false),
                    DatabaseId = table.Column<Guid>(type: "uuid", nullable: true),
                    PluginId = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    ParametersJson = table.Column<string>(type: "text", nullable: true),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_assessment_job", x => x.JobId);
                    table.ForeignKey(
                        name: "FK_assessment_job_agent_AgentId",
                        column: x => x.AgentId,
                        principalSchema: "assessment",
                        principalTable: "agent",
                        principalColumn: "AgentId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_assessment_job_database_instance_DatabaseId",
                        column: x => x.DatabaseId,
                        principalSchema: "inventory",
                        principalTable: "database_instance",
                        principalColumn: "DatabaseId");
                });

            migrationBuilder.CreateTable(
                name: "assessment_result",
                schema: "assessment",
                columns: table => new
                {
                    ResultId = table.Column<Guid>(type: "uuid", nullable: false),
                    JobId = table.Column<Guid>(type: "uuid", nullable: false),
                    DatabaseId = table.Column<Guid>(type: "uuid", nullable: true),
                    PluginId = table.Column<string>(type: "text", nullable: false),
                    PluginVersion = table.Column<string>(type: "text", nullable: false),
                    Confidence = table.Column<int>(type: "integer", nullable: false),
                    FindingJson = table.Column<string>(type: "jsonb", nullable: false),
                    RawSummaryJson = table.Column<string>(type: "jsonb", nullable: false),
                    PayloadHash = table.Column<string>(type: "text", nullable: true),
                    AssessedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_assessment_result", x => x.ResultId);
                    table.ForeignKey(
                        name: "FK_assessment_result_assessment_job_JobId",
                        column: x => x.JobId,
                        principalSchema: "assessment",
                        principalTable: "assessment_job",
                        principalColumn: "JobId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_assessment_result_database_instance_DatabaseId",
                        column: x => x.DatabaseId,
                        principalSchema: "inventory",
                        principalTable: "database_instance",
                        principalColumn: "DatabaseId");
                });

            migrationBuilder.CreateIndex(
                name: "IX_agent_EnvironmentId",
                schema: "assessment",
                table: "agent",
                column: "EnvironmentId");

            migrationBuilder.CreateIndex(
                name: "IX_agent_ProjectId_EnvironmentId",
                schema: "assessment",
                table: "agent",
                columns: new[] { "ProjectId", "EnvironmentId" });

            migrationBuilder.CreateIndex(
                name: "IX_assessment_job_AgentId_Status",
                schema: "assessment",
                table: "assessment_job",
                columns: new[] { "AgentId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_assessment_job_DatabaseId",
                schema: "assessment",
                table: "assessment_job",
                column: "DatabaseId");

            migrationBuilder.CreateIndex(
                name: "IX_assessment_result_DatabaseId",
                schema: "assessment",
                table: "assessment_result",
                column: "DatabaseId");

            migrationBuilder.CreateIndex(
                name: "IX_assessment_result_JobId",
                schema: "assessment",
                table: "assessment_result",
                column: "JobId");

            migrationBuilder.CreateIndex(
                name: "IX_database_instance_EnvironmentId",
                schema: "inventory",
                table: "database_instance",
                column: "EnvironmentId");

            migrationBuilder.CreateIndex(
                name: "IX_database_instance_ProjectId_EnvironmentId",
                schema: "inventory",
                table: "database_instance",
                columns: new[] { "ProjectId", "EnvironmentId" });

            migrationBuilder.CreateIndex(
                name: "IX_environment_ProjectId",
                schema: "core",
                table: "environment",
                column: "ProjectId");

            migrationBuilder.CreateIndex(
                name: "IX_project_CustomerId",
                schema: "core",
                table: "project",
                column: "CustomerId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "assessment_result",
                schema: "assessment");

            migrationBuilder.DropTable(
                name: "assessment_job",
                schema: "assessment");

            migrationBuilder.DropTable(
                name: "agent",
                schema: "assessment");

            migrationBuilder.DropTable(
                name: "database_instance",
                schema: "inventory");

            migrationBuilder.DropTable(
                name: "environment",
                schema: "core");

            migrationBuilder.DropTable(
                name: "project",
                schema: "core");

            migrationBuilder.DropTable(
                name: "customer",
                schema: "core");
        }
    }
}
