/**
 * @file
 * Theme behaviors for STARTER theme.
 */

(function (Drupal, once) {
  'use strict';

  /**
   * Example behavior — rename and customize.
   *
   * @type {Drupal~behavior}
   */
  Drupal.behaviors.starterExample = {
    attach(context) {
      once('starter-example', '[data-starter-example]', context).forEach(
        (element) => {
          // Initialize component here.
        },
      );
    },
  };
})(Drupal, once);
