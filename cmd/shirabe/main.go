package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/tsukumogami/shirabe/internal/annotation"
	"github.com/tsukumogami/shirabe/internal/validate"
	"gopkg.in/yaml.v3"
)

func main() {
	if err := rootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}

func rootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "shirabe",
		Short: "Workflow skills for AI coding agents",
	}
	root.AddCommand(validateCmd())
	return root
}

func validateCmd() *cobra.Command {
	var visibility string
	var customStatusesStr string

	cmd := &cobra.Command{
		Use:   "validate [files...]",
		Short: "Validate shirabe doc files",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 {
				return nil
			}

			var customStatuses map[string][]string
			if customStatusesStr != "" {
				if len(customStatusesStr) > 64*1024 {
					return fmt.Errorf("--custom-statuses value exceeds maximum allowed size (64 KiB)")
				}
				if err := yaml.Unmarshal([]byte(customStatusesStr), &customStatuses); err != nil {
					return fmt.Errorf("--custom-statuses contains invalid YAML: %w", err)
				}
			}

			cfg := validate.Config{
				CustomStatuses: customStatuses,
				Visibility:     visibility,
			}

			hasErrors := false
			for _, path := range args {
				basename := filepath.Base(path)
				spec, ok := validate.DetectFormat(basename)
				if !ok {
					continue
				}

				doc, err := validate.ParseDoc(path)
				if err != nil {
					fmt.Println(annotation.FormatError(validate.ValidationError{
						File:    path,
						Line:    1,
						Code:    "IO",
						Message: fmt.Sprintf("could not read file: %v", err),
					}))
					hasErrors = true
					continue
				}

				errs := validate.ValidateFile(doc, spec, cfg)
				for _, ve := range errs {
					if validate.IsNotice(ve) {
						fmt.Println(annotation.FormatNotice(ve.File, ve.Message))
					} else {
						fmt.Println(annotation.FormatError(ve))
						hasErrors = true
					}
				}
			}

			if hasErrors {
				os.Exit(1)
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&visibility, "visibility", "", "visibility context (public|private)")
	cmd.Flags().StringVar(&customStatusesStr, "custom-statuses", "", "YAML map of schema version to valid status list")
	return cmd
}
