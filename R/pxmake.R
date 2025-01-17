#' Get the main language from metadata
#'
#' @inheritParams sort_metadata_df
#'
#' @returns Character
get_main_language <- function(metadata_df) {
  metadata_df %>%
    dplyr::filter(keyword == "LANGUAGE") %>%
    tidyr::unnest(value) %>%
    dplyr::pull(value)
}

#' Impute missing language
#'
#' Add main language as language if language is missing.
#'
#' @inheritParams sort_metadata_df
#'
#' @returns A data frame
replace_na_language_with_main_language <- function(metadata_df) {
  metadata_df %>%
    dplyr::mutate(language = tidyr::replace_na(language, get_main_language(.)))
}

#' Add boolean main_language column
#'
#' @inheritParams sort_metadata_df
#'
#' @returns A data frame
add_main_language <- function(metadata_df) {
  metadata_df %>%
    replace_na_language_with_main_language() %>%
    dplyr::mutate(main_language = language == get_main_language(.))
}

#' Get variable code and label
#'
#' Get a data frame with variable codes and label in all languages.
#' If VARIABLECODE is used, the relation is defined there, but otherwise the
#' variable code is set to be the main languages' label.
#'
#' @inheritParams sort_metadata_df
#'
#' @returns A data frame
get_variable_label <- function(metadata_df) {
  metadata_df <- add_main_language(metadata_df)

  head_stub <-
    metadata_df %>%
    dplyr::filter(keyword %in% c("HEADING", "STUB")) %>%
    tidyr::unnest(value) %>%
    dplyr::rename(`variable-label` = value) %>%
    dplyr::group_by(keyword, language) %>%
    dplyr::mutate(index = dplyr::row_number()) %>%
    dplyr::ungroup() %>%
    dplyr::select(keyword, language, main_language, `variable-label`, index)

  head_stub_main_language <-
    dplyr::filter(head_stub, main_language) %>%
    dplyr::rename(main_language_label = `variable-label`) %>%
    dplyr::select(keyword, index, main_language_label)

  metadata_df %>%
    dplyr::filter(keyword == "VARIABLECODE") %>%
    tidyr::unnest(value) %>%
    dplyr::select(`variable-code` = value,
                  `variable-label` = variable,
                  language,
                  main_language
                  ) %>%
    dplyr::full_join(head_stub,
                     by = c("variable-label", "language", "main_language")
                     ) %>%
    dplyr::left_join(head_stub_main_language, by = c("keyword", "index")) %>%
    dplyr::mutate(`variable-code` = ifelse(is.na(`variable-code`),
                                           main_language_label,
                                           `variable-code`
                                           )
                  ) %>%
    dplyr::select(-main_language_label)
}

#' Get the name of figures variable
#'
#' @inheritParams get_data_df
#'
#' @returns Character
get_figures_variable <- function(input, data) {
  if (is_rds_file(input)) {
    input <- readRDS(input)
  } else if (is.data.frame(input)) {
    if (is_rds_file(data)) {
      data <- readRDS(data)
    }
    input <- list("metadata" = input, "data" = data)
  }

  if (is_xlsx_file(input)) {
    figures_var <-
      input %>%
        get_variables_sheet() %>%
        dplyr::filter(toupper(pivot) == "FIGURES") %>%
        dplyr::distinct(`variable-code`) %>%
        dplyr::pull(`variable-code`)
  } else if (is_rds_list(input)) {
    non_figure_variables <-
      get_variable_label(input$metadata) %>%
      dplyr::filter(!is.na(keyword), main_language) %>%
      dplyr::pull(`variable-code`)

    data_variables <- names(input$data)

    figures_var <- setdiff(data_variables, non_figure_variables)
  } else {
    unexpected_error()
  }

  error_if_not_exactly_one_figures_variable(figures_var)
  return(figures_var)
}

#' Get data frame from data argument
#'
#' @inheritParams pxmake
#'
#' @returns A data frame
get_raw_data <- function(input, data) {
  if (is_xlsx_file(input) & is.null(data)) {
    return(get_data_sheet(input))
  } else if (is_rds_file(input)) {
    return(readRDS(input)$data)
  } else if (is_rds_list(input)) {
    return(input$data)
  } else if (is.data.frame(data)) {
    return(data)
  } else if (is_rds_file(data)) {
    return(readRDS(data))
  } else {
    unexpected_error()
  }
}

#' Get data frame from metadata argument
#'
#' @inheritParams pxmake
#' @inheritParams get_metadata_df_from_excel
get_metadata_df <- function(input, data_df) {
  if (is_xlsx_file(input)) {
    return(get_metadata_df_from_excel(input, data_df))
  } else if (is_rds_file(input)) {
    return(readRDS(input)$metadata)
  } else if (is_rds_list(input)) {
    return(input$metadata)
  } else if (is.data.frame(input)) {
    return(input)
  } else {
    unexpected_error()
  }
}

#' Get data as data frame
#'
#' @inheritParams pxmake
#'
#' @returns A data frame
get_data_df  <- function(input, data, add_totals) {
  data_df <-
    get_raw_data(input, data) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(across(-one_of(get_figures_variable(input, data)),
                         as.character
                         )
                  )

  if (!is.null(add_totals)) {
    data_df <- add_totals_to_data_df(input, data_df, add_totals)
  }

  return(data_df)
}

#' Get encoding name from metadata
#'
#' @inherit get_main_language
get_encoding_from_metadata <- function(metadata_df) {
  encoding_str <-
    metadata_df %>%
    dplyr::filter(keyword == "CODEPAGE") %>%
    tidyr::unnest(value) %>%
    dplyr::pull(value)

  if (length(encoding_str) == 0) {
    encoding_str <- get_default_encoding()
  }

  return(encoding_str)
}

#' Sort metadata data frame
#'
#' The data frame is first sorted by the keyword order defined in the
#' px-specification and then by the language order.
#'
#' @param metadata_df Data frame with metadata.
#'
#' @returns A data frame
sort_metadata_df <- function(metadata_df) {
  languages <-
    metadata_df %>%
    dplyr::filter(keyword == "LANGUAGES") %>%
    tidyr::unnest(value) %>%
    dplyr::mutate(language_order = dplyr::row_number()) %>%
    dplyr::select(language = value, language_order)

  metadata_df %>%
    dplyr::left_join(get_px_keywords() %>% dplyr::select('keyword', 'order'),
                     by = "keyword"
                     ) %>%
    dplyr::left_join(languages, by = "language") %>%
    dplyr::arrange(order, keyword, language_order,
                   !is.na(variable), variable, cell
                   ) %>%
    dplyr::select(-order, -language_order)
}

#' Get a data frame with metadata
#'
#' The metadata from the 3 sheets in the Excel workbook are combined into one
#' data frame, in a format that's both easy to read, query and convert to a
#' px-file.
#'
#' @param excel_metadata_path Path to xlsx workbook with metadata.
#' @param data_df Data frame with data in tidy format.
#'
#' @returns A data frame
get_metadata_df_from_excel <- function(excel_metadata_path, data_df) {
  df <- dplyr::tibble(keyword  = character(),
                      language = character(),
                      variable = character(),
                      cell     = character(),
                      value    = list(character())
                      )

  variables_long <-
    excel_metadata_path %>%
    get_variables_metadata() %>%
    tidyr::pivot_longer(cols = -c(pivot, order, `variable-code`, type, language,
                                  `variable-label`
                                  ),
                        names_to = "keyword"
                        )

  note_etc <-
    variables_long %>%
    tidyr::drop_na(value) %>%
    dplyr::mutate(keyword = toupper(keyword)) %>%
    wrap_varaible_in_list(value) %>%
    dplyr::select(keyword, variable = `variable-label`, language, value) %>%
    dplyr::arrange_all()

  variablecode <-
    variables_long %>%
    dplyr::distinct(keyword = "VARIABLECODE",
                    value = `variable-code`,
                    variable = `variable-label`,
                    language
                    ) %>%
    wrap_varaible_in_list(value)

  head_stub <-
    variables_long %>%
    dplyr::filter(toupper(pivot) %in% c("STUB", "HEADING")) %>%
    dplyr::distinct(pivot, order, `variable-code`, language, `variable-label`) %>%
    dplyr::mutate(keyword = toupper(pivot)) %>%
    dplyr::arrange(keyword, order) %>%
    dplyr::group_by(keyword, language) %>%
    dplyr::summarise(value = list(paste(`variable-label`, sep = ", ")),
                     .groups = "keep"
                     )

  time_metadata <-
    variables_long %>%
    dplyr::filter(tolower(type) == "time") %>%
    dplyr::distinct(`variable-code`, language, `variable-label`)

  time_variable <-
    time_metadata %>%
    dplyr::distinct(`variable-code`) %>%
    dplyr::pull(`variable-code`)

  if (length(time_variable) == 0) {
    timeval <- NULL
  } else {
    error_if_more_than_one_time_variable(time_variable)

    time_values <-
      data_df %>%
      dplyr::distinct(across(all_of(time_variable))) %>%
      dplyr::pull(1)

    timeval <-
      time_metadata %>%
      dplyr::mutate(keyword = "TIMEVAL",
                    value = paste0("TLIST(",
                                   get_timeval_type_from_values(time_values),
                                   "1),",
                                   time_values %>%
                                     stringr::str_replace_all('[:alpha:]', '') %>%
                                     str_quote() %>%
                                     stringr::str_c(collapse = ',')
                                   )
                    ) %>%
      dplyr::select(keyword, language, variable = `variable-label`, value) %>%
      wrap_varaible_in_list(value)
  }

  codelists <- get_codelists_metadata(excel_metadata_path, data_df)

  code_value <-
    codelists %>%
    tidyr::pivot_longer(cols = c("code",  "value"), names_to = "type") %>%
    # Update when implementing #140
    dplyr::mutate(keyword = toupper(paste0(type, "s"))) %>%
    dplyr::arrange(keyword, sortorder) %>%
    dplyr::group_by(keyword, language, variable = `variable-label`) %>%
    dplyr::summarise(value = list(paste(value, sep = ", ")), .groups = "keep") %>%
    dplyr::ungroup()

  precision <-
    codelists %>%
    dplyr::mutate(keyword = "PRECISION") %>%
    tidyr::drop_na(precision) %>%
    wrap_varaible_in_list(precision) %>%
    dplyr::select(keyword,
                  language,
                  variable = `variable-label`,
                  cell = value,
                  value = precision
                  )

  table_language_dependent <-
    get_table2_metadata(excel_metadata_path) %>%
    dplyr::left_join(dplyr::select(codelists, code, language, cell = value),
                     by = c("code", "language")
                     ) %>%
    dplyr::select(-code)


  metadata_df <-
    dplyr::bind_rows(df,
                     get_table_metadata(excel_metadata_path),
                     table_language_dependent,
                     variablecode,
                     note_etc,
                     head_stub,
                     timeval,
                     code_value,
                     precision
                     ) %>%
    replace_na_language_with_main_language() %>%
    sort_metadata_df()
}

#' Get data cube used in px file format
#'
#' @inheritParams sort_metadata_df
#' @inheritParams get_metadata_df_from_excel
#'
#' @returns A data frame
get_data_cube <- function(metadata_df, data_df) {
  metadata_df <- add_main_language(metadata_df)

  metadata_df_main_language <-
    metadata_df %>%
    dplyr::filter(main_language)

  labels <-
    metadata_df_main_language %>%
    dplyr::filter(keyword == "VARIABLECODE") %>%
    tidyr::unnest(value) %>%
    dplyr::select(label = variable, variable = value)

  stub_and_heading_df <-
    metadata_df_main_language %>%
    dplyr::filter(keyword %in% c("STUB", "HEADING")) %>%
    tidyr::unnest(value) %>%
    dplyr::select(keyword, label = value) %>%
    dplyr::left_join(labels, by = "label") %>%
    dplyr::mutate(variable = ifelse(is.na(variable),
                                    label,
                                    variable
                                    )
                  )

  stub_vars <-
    stub_and_heading_df %>%
    dplyr::filter(keyword == "STUB") %>%
    dplyr::pull(variable)

  heading_vars <-
    stub_and_heading_df %>%
    dplyr::filter(keyword == "HEADING") %>%
    dplyr::pull(variable)

  head_stub_variable_names <- c(heading_vars, stub_vars)

  figures_var <- setdiff(names(data_df),  head_stub_variable_names)

  error_if_not_exactly_one_figures_variable(figures_var)

  codelist <-
    metadata_df %>%
    dplyr::filter(keyword == "CODES", main_language) %>%
    dplyr::select(keyword, variable, value) %>%
    tidyr::unnest(value) %>%
    dplyr::rename(label = variable) %>%
    dplyr::group_by(label) %>%
    dplyr::mutate(sortorder = dplyr::row_number()) %>%
    dplyr::ungroup() %>%
    dplyr::left_join(labels, by = "label") %>%
    dplyr::select(variable, sortorder, code = value)

  # Complete data by adding all combinations of variable values in data and
  # codelist
  data_values <-
    data_df %>%
    dplyr::select(dplyr::all_of(head_stub_variable_names)) %>%
    lst_distinct_and_arrange()

  codelist_values <-
    split(codelist$code, codelist$variable) %>%
    lst_distinct_and_arrange()

  data_and_codelist_values <- merge_named_lists(data_values, codelist_values)

  heading_code_vars      <- paste0("code_",      heading_vars, recycle0 = TRUE)
  heading_sortorder_vars <- paste0("sortorder_", heading_vars, recycle0 = TRUE)
  stub_code_vars         <- paste0("code_",      stub_vars,    recycle0 = TRUE)
  stub_sortorder_vars    <- paste0("sortorder_", stub_vars,    recycle0 = TRUE)

  data_cube <-
    data_df %>%
    tidyr::complete(!!!data_and_codelist_values) %>%
    dplyr::mutate(id_ = dplyr::row_number()) %>% # used to unpivot data later
    tidyr::pivot_longer(cols = all_of(head_stub_variable_names),
                        names_to = "variable",
                        values_to = "code"
                        ) %>%
    dplyr::left_join(codelist, by = c("variable", "code")) %>%
    tidyr::pivot_wider(names_from = variable,
                       values_from = c("code", "sortorder")
                       ) %>%
    dplyr::select(-id_) %>%
    # Sort by sortorder for first heading var, codes for first heading var,
    # sortorder for second heading var, etc.
    dplyr::arrange(dplyr::across(zip_vectors(heading_sortorder_vars, heading_code_vars))) %>%
    dplyr::select(-all_of(heading_sortorder_vars)) %>%
    { if(length(heading_code_vars > 0)) {
      tidyr::pivot_wider(.,
                         names_from = all_of(heading_code_vars),
                         values_from = all_of(figures_var)
                         )
      } else {
        .
      }
    } %>%
    dplyr::arrange(dplyr::across(zip_vectors(stub_sortorder_vars, stub_code_vars))) %>%
    dplyr::select(-ends_with(paste0("_", stub_vars)))

  return(data_cube)
}

#' Turn metadata and data cube into px lines
#'
#' @inheritParams get_data_cube
#'
#' @returns A character vector
format_data_as_px_lines <- function(metadata_df, data_df) {
  time_variables <-
    metadata_df %>%
    dplyr::filter(keyword == "TIMEVAL") %>%
    dplyr::pull(variable)

  metadata_lines <-
    metadata_df %>%
    dplyr::left_join(dplyr::select(get_px_keywords(), keyword, quote_value),
                     by = 'keyword'
                     ) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(keyword = keyword %>%
                              add_language_to_keyword(get_main_language(metadata_df),
                                                      language
                                                      ) %>%
                              add_sub_key_to_keyword(variable) %>%
                              add_cell_to_keyword(cell)
                  ) %>%
    dplyr::mutate(value = value %>%
                            tidyr::replace_na("") %>%
                            paste(collapse = '","') %>%
                            ifelse(quote_value,
                                   quote_unless_yes_no(.),
                                   .
                                   ) %>%
                            break_long_lines(max_line_length = 256) %>%
                            list()
                  ) %>%
    dplyr::ungroup() %>%
    tidyr::unnest(value) %>%
    dplyr::mutate(repeated_keyword = !is.na(dplyr::lag(keyword)) &
                                     keyword == dplyr::lag(keyword),
                  last = is.na(dplyr::lead(repeated_keyword)) |
                         !dplyr::lead(repeated_keyword)
                  ) %>%
    dplyr::mutate(line = stringr::str_c(ifelse(repeated_keyword,
                                               "",
                                               paste0(keyword, "=")
                                               ),
                                        value,
                                        ifelse(last, ";", "")
                                        )
                  ) %>%
    dplyr::pull(line)

  data_cube <- get_data_cube(metadata_df, data_df)

  data_lines <-
    data_cube %>%
    mutate_all_vars_to_character() %>%
    dplyr::mutate(dplyr::across(everything(), ~tidyr::replace_na(.x, '"-"'))) %>%
    tidyr::unite(tmp, sep = " ") %>%
    dplyr::pull(tmp)

  c(metadata_lines, "DATA=", data_lines, ";")
}

#' Save output form pxmake to out_path
#'
#' @inheritParams pxmake
#' @inheritParams get_data_cube
#'
#' @returns rds object
save_pxmake_output <- function(out_path, metadata_df, data_df) {
  metadata_df <- sort_metadata_df(metadata_df)

  rds <- list("metadata" = metadata_df, "data" = data_df)

  if (is_rds_file(out_path)) {
    saveRDS(rds, out_path)
  } else if (is_px_file(out_path)) {
    px_lines <- format_data_as_px_lines(metadata_df, data_df)

    write_lines_to_file(px_lines, out_path, get_encoding_from_metadata(metadata_df))
  } else if(is.null(out_path)) {
    # pass
  } else {
    unexpected_error()
  }

  return(rds)
}

#' Create a px-file from metadata and data
#'
#' @param input Metadata can be provided in one of four ways:
#' 1. A path to an `.xlsx` metadata file.
#' 1. A path to an `.rds` file created by \link{metamake}.
#' 1. A named list with two data frames "metadata" and "data" (like
#' \link{metamake} `.rds` file).
#' 1. A data frame with metadata (metadata part of `.rds` file by
#' \link{metamake}.)
#' @param out_path Path to save output at, either as an `.rds` or `.px` file.
#' If NULL, no file is saved.
#' @param data Either a data frame, or a path to an `.rds` file. If NULL,
#' the data must be provided as part of the `metadata` argument, either in
#' option 1. as the sheet 'Data' in the Excel metadata workbook, or as the
#' "data" in option 2 or 3.
#' @param add_totals A list of variables to add a 'total' level to. The option
#' is only available if `input` is an `.xlsx` file (option 1). The value of the
#' total level is looked up in 'Variables' xx_elimination. The code for the
#' level is found in 'Codelists'. The total is a sum of the values in the
#' variables with `pivot = FIGURES` in 'Variables'. NAs are ignored when summing.
#'
#' @returns Returns rds object invisibly.
#'
#' @seealso \link{metamake}
#'
#' @export
pxmake <- function(input,
                   out_path = NULL,
                   data = NULL,
                   add_totals = NULL) {

  validate_pxmake_arguments(input, out_path, data, add_totals)

  data_df <- get_data_df(input, data, add_totals)
  metadata_df <- get_metadata_df(input, data_df)

  rds <- save_pxmake_output(out_path, metadata_df, data_df)

  invisible(rds)
}
