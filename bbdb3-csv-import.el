;;; bbdb3-csv-import.el  --- import csv to bbdb version 3+ -*- lexical-binding: t; -*-

;; Copyright (C) 2014 by Ian Kelling

;; Author: Ian Kelling <ian@iankelling.org>
;; Created: 1 Apr 2014
;; Version: 1.0
;; Keywords: csv, util, bbdb

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Importer of csv (comma separated value) text into Emacs’s bbdb database,
;; version 3+. Programs such as Thunderbird and Outlook allow for exporting
;; contact data as csv files.

;;; Installation:
;;
;; dependencies: pcsv.el, dash.el, bbdb
;; These are available via marmalade/melpa or the internet
;;
;; Add to init file or execute manually as this may be a one time usage:
;; (load-file FILENAME-OF-THIS-FILE)
;; or
;; (add-to-list 'load-path DIRECTORY-CONTAINING-THIS-FILE)
;; (require 'bbdb3-csv-import)

;;; Usage:
;;
;; Backup or rename any existing ~/.bbdb and ~/.emacs.d/bbdb while testing that
;; the import works correctly.
;;
;; Assign bbdb3-csv-import-mapping-table to a mapping table. Some are predefined
;; below, ie. bbdb3-csv-import-thunderbird.
;;
;; Simply call `bbdb3-csv-import-buffer' or
;; `bbdb3-csv-import-file'. Interactively they prompt for file/buffer. Use
;; non-interactively for no prompts.
;;
;; Thunderbird csv data works out of the box. Otherwise you will need to create
;; a mapping table to suit your data and assign it to
;; bbdb3-csv-import-mapping-table. Note that variable's doc string and perhaps
;; the test data within this project for more details. Please send any new
;; mapping tables upstream so I can add it to this file for other's benefit. I,
;; Ian Kelling, am willing to help with any issues including creating a mapping
;; table given sample data.
;;
;; Tips for testing: bbdb doesn't work if you delete the bbdb database file in
;; the middle of an emacs session. If you want to empty the current bbdb database,
;; do M-x bbdb then .* then C-u * d on the beginning of a record.

(require 'pcsv)
(require 'dash)
(require 'bbdb-com)
(eval-when-compile (require 'cl))

(defconst bbdb3-csv-import-thunderbird
  '(("firstname" "First Name")
    ("lastname" "Last Name")
    ("name" "Display Name")
    ("aka" "Nickname")
    ("mail" "Primary Email" "Secondary Email")
    ("phone" "Work Phone" "Home Phone" "Fax Number" "Pager Number" "Mobile Number")
    ("address"
     ("home address" (("Home Address"
                       "Home Address 2")
                      "Home City"
                      "Home State"
                      "Home ZipCode"
                      "Home Country"))
     ("work address" (("Work Address"
                       "Work Address 2")
                      "Work City"
                      "Work State"
                      "Work ZipCode"
                      "Work Country")))
    ("organization" "Organization")
    ("xfields" "Web Page 1" "Web Page 2" "Birth Year" "Birth Month"
     "Birth Day" "Department" "Custom 1" "Custom 2" "Custom 3"
     "Custom 4" "Notes" "Job Title"))
  "Thunderbird csv format")

(defconst bbdb3-csv-import-linkedin
  '(("firstname" "First Name")
    ("lastname" "Last Name")
    ("middlename" "Middle Name")
    ("mail" "E-mail Address" "E-mail 2 Address" "E-mail 3 Address")
    ("phone" "Assistant's Phone" "Business Fax" "Business Phone" "Business Phone 2" "Callback" "Car Phone" "Company Main Phone" "Home Fax" "Home Phone" "Home Phone 2" "ISDN" "Mobile Phone" "Other Fax" "Other Phone" "Pager" "Primary Phone" "Radio Phone" "TTY/TDD Phone" "Telex")
    ("address"
     ("business address" (("Business Street"
                           "Business Street 2"
                           "Business Street 3")
                          "Business City"
                          "Business State"
                          "Business Postal Code"
                          "Business Country"))
     ("home address" (("Home Street"
                       "Home Street 2"
                       "Home Street 3")
                      "Home City"
                      "Home State"
                      "Home Postal Code"
                      "Home Country"))
     ("other address" (("Other Street"
                        "Other Street 2"
                        "Other Street 3")
                       "Other City"
                       "Other State"
                       "Other Postal Code"
                       "Other Country")))
    ("organization" "Company")
    ("xfields" "Suffix" "Department" "Job Title" "Assistant's Name" "Birthday" "Manager's Name" "Notes" "Other Address PO Box" "Spouse" "Web Page" "Personal Web Page"))
  "Linkedin export in the Outlook csv format.")


(defvar bbdb3-csv-import-mapping-table nil
  "The table which maps bbdb3 fields to csv fields.
Use the default as an example to map non-thunderbird data.
Name used is firstname + lastname or name.
After the car, all names should map to whatever csv
field names are used in the first row of csv data.
Many fields are optional. If you aren't sure if one is,
best to just try it. The doc string for `bbdb-create-internal'
may be useful for determining which fields are required.")

;;;###autoload
(defun bbdb3-csv-import-file (filename)
  "Parse and import csv file FILENAME to bbdb3."
  (interactive "fCSV file containg contact data: ")
  (bbdb3-csv-import-buffer (find-file-noselect filename)))


;;;###autoload
(defun bbdb3-csv-import-buffer (&optional buffer-or-name) 
  "Parse and import csv BUFFER-OR-NAME to bbdb3.
Argument is a buffer or name of a buffer.
Defaults to current buffer."
  (interactive "bBuffer containing CSV contact data: ")
  (let* ((csv-fields (pcsv-parse-buffer (get-buffer (or buffer-or-name (current-buffer)))))
         (csv-contents (cdr csv-fields))
         (csv-fields (car csv-fields))
         (initial-duplicate-value bbdb-allow-duplicates)
         csv-record)
    ;; Easier to allow duplicates and handle them post import vs failing as
    ;; soon as we find one.
    (setq bbdb-allow-duplicates t)
    (while (setq csv-record (map 'list 'cons csv-fields (pop csv-contents)))
      (cl-flet* 
          ((rd (func list) (bbdb3-csv-import-reduce func list)) ;; just a local defalias
           (assoc-plus (key list) (bbdb3-csv-import-assoc-plus key list)) ;; defalias
           (rd-assoc (list) (rd (lambda (elem) (assoc-plus elem csv-record)) list))
           (mapcar-assoc (list) (mapcar (lambda (elem) (cdr (assoc elem csv-record))) list))
           (field-map (field) (cdr (assoc field bbdb3-csv-import-mapping-table)))
           (map-assoc (field) (assoc-plus (car (field-map field)) csv-record)))
        
        (let ((name (let ((first (map-assoc "firstname"))
                          (middle (map-assoc "middlename"))
                          (last (map-assoc "lastname"))
                          (name (map-assoc "name")))
                      ;; prioritize any combination of first middle last over just "name"
                      (if (or (and first last) (and first middle) (and middle last))
                          ;; purely historical note.
                          ;; it works exactly the same but I don't use (cons first last) due to a bug
                          ;; http://www.mail-archive.com/bbdb-info%40lists.sourceforge.net/msg06388.html
                          (concat (or first middle) " " (or middle last) (when (and first middle) (concat " " last) ))
                        (or name first middle last ""))))
              (phone (rd (lambda (mapping-elem)
                           (let ((data (assoc-plus mapping-elem csv-record)))
                             (if data (vconcat (list mapping-elem data)))))
                         (field-map "phone")))
              (xfields (rd (lambda (mapping-elem)
                             (let ((value (assoc-plus mapping-elem csv-record)))
                               (when value
                                 (while (string-match " " mapping-elem)
                                   ;; turn csv field names into symbols for extra fields
                                   (setq mapping-elem (replace-match "" nil nil mapping-elem)))
                                 (cons (make-symbol (downcase mapping-elem)) value))))
                           (field-map "xfields")))
              (address (rd (lambda (mapping-elem)
                             (let ((address-lines (mapcar-assoc (caadr mapping-elem)))
                                   (address-data (mapcar-assoc (cdadr mapping-elem))))
                               ;; determine if non-nil and put together the  minimum set
                               (when (or (not (-all? '(lambda (arg) (zerop (length arg))) address-data))
                                         (not (-all? '(lambda (arg) (zerop (length arg))) address-lines)))
                                 (when (> 2 (length address-lines))
                                   (setcdr (max 2 (nthcdr (-find-last-index (lambda (mapping-elem) (not (null mapping-elem)))
                                                                            address-lines)
                                                          address-lines)) nil))
                                 (vconcat (list (car mapping-elem)) (list address-lines) address-data))))
                           (field-map "address")))
              (mail (rd-assoc (field-map "mail")))
              (organization (rd-assoc (field-map "organization")))
              (affix (map-assoc "affix"))
              (aka (rd-assoc (field-map "aka"))))
          (bbdb-create-internal name affix aka organization mail
                                phone address xfields t))))
    (setq bbdb-allow-duplicates initial-duplicate-value)))


;;;###autoload
(defun bbdb3-csv-import-reduce (func list)
  "like mapcar but don't build nil results into the resulting list"
  (-reduce-from (lambda (acc elem)
                  (let ((funcreturn (funcall func elem)))
                    (if funcreturn
                        (cons funcreturn acc)
                      acc)))
                nil list))

;;;###autoload
(defun bbdb3-csv-import-assoc-plus (key list)
  "Like `assoc' but turn an empty string result to nil."
  (let ((result (cdr (assoc key list))))
    (when (not (string= "" result))
      result)))

(provide 'bbdb3-csv-import)

;;; bbdb3-csv-import.el ends here

